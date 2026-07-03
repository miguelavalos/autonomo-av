#!/usr/bin/env bash
set -euo pipefail

macos_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
env_name=""
configuration="Debug"

usage() {
  cat <<'USAGE'
Usage:
  scripts/check-macos-runtime-config.sh --env dev|prod [--configuration Debug|Release]

Validates effective Autonomo AV macOS build settings without printing secrets.
Dev may compile with Account AV runtime values inherited; prod must resolve all
runtime values to concrete production settings.
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --env)
      env_name="${2:-}"
      shift 2
      ;;
    --configuration)
      configuration="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [ "$env_name" != "dev" ] && [ "$env_name" != "prod" ]; then
  echo "--env must be dev or prod." >&2
  exit 2
fi
if [ "$configuration" != "Debug" ] && [ "$configuration" != "Release" ]; then
  echo "--configuration must be Debug or Release." >&2
  exit 2
fi

app_settings_file="$(mktemp)"
share_settings_file="$(mktemp)"
trap 'rm -f "$app_settings_file" "$share_settings_file"' EXIT

xcodebuild \
  -project "$macos_root/AutonomoAVMac.xcodeproj" \
  -target AutonomoAVMac \
  -configuration "$configuration" \
  -showBuildSettings > "$app_settings_file"

xcodebuild \
  -project "$macos_root/AutonomoAVMac.xcodeproj" \
  -target AutonomoAVMacShareExtension \
  -configuration "$configuration" \
  -showBuildSettings > "$share_settings_file"

setting_from() {
  local file="$1"
  local key="$2"
  awk -F= -v wanted="$key" '
    $1 ~ "^[[:space:]]*" wanted "[[:space:]]*$" {
      value=$2
      sub(/^[[:space:]]+/, "", value)
      sub(/[[:space:]]+$/, "", value)
      print value
      exit
    }
  ' "$file"
}

app_setting() {
  setting_from "$app_settings_file" "$1"
}

share_setting() {
  setting_from "$share_settings_file" "$1"
}

failures=0
fail() {
  printf 'FAIL %s\n' "$1" >&2
  failures=$((failures + 1))
}

is_missing() {
  local value="$1"
  [ -z "$value" ] || [ "$value" = "\$(inherited)" ]
}

require_present() {
  local label="$1"
  local value="$2"
  if is_missing "$value"; then
    fail "$label must resolve to a real value"
  fi
}

allow_https_or_dev_local_url() {
  local name="$1"
  local value="$2"

  if is_missing "$value"; then
    if [ "$env_name" = "prod" ]; then
      fail "$name must resolve to a real value for prod"
    fi
    return
  fi

  if [[ "$value" == https://* ]]; then
    return
  fi
  if [ "$env_name" = "dev" ]; then
    case "$value" in
      http://127.0.0.1:*|http://localhost:*) return ;;
    esac
  fi

  fail "$name did not resolve as https://* or a dev localhost URL: $value"
}

product_bundle_identifier="$(app_setting PRODUCT_BUNDLE_IDENTIFIER)"
autonomo_bundle_identifier="$(app_setting AUTONOMOAV_MACOS_BUNDLE_IDENTIFIER)"
app_group_identifier="$(app_setting AUTONOMOAV_APP_GROUP_IDENTIFIER)"
config_environment="$(app_setting AUTONOMOAV_CONFIG_ENVIRONMENT)"
api_base_url="$(app_setting ACCOUNTAV_API_BASE_URL)"
autonomo_api_base_url="$(app_setting AUTONOMOAV_API_BASE_URL)"
management_url="$(app_setting ACCOUNTAV_MANAGEMENT_URL)"
publishable_key="$(app_setting ACCOUNTAV_PUBLISHABLE_KEY)"
keychain_service="$(app_setting ACCOUNTAV_KEYCHAIN_SERVICE)"
keychain_access_group="$(app_setting ACCOUNTAV_KEYCHAIN_ACCESS_GROUP)"
support_base_url="$(app_setting SUPPORTAV_BASE_URL)"
support_email="$(app_setting SUPPORT_EMAIL_TO)"
delete_account_url="$(app_setting AUTONOMOAV_DELETE_ACCOUNT_URL)"
terms_url="$(app_setting AUTONOMOAV_TERMS_URL)"
privacy_url="$(app_setting AUTONOMOAV_PRIVACY_URL)"
autonomoav_macos_sentry_dsn="$(app_setting AUTONOMOAV_MACOS_SENTRY_DSN)"
development_team="$(app_setting DEVELOPMENT_TEAM)"
code_sign_style="$(app_setting CODE_SIGN_STYLE)"
enable_hardened_runtime="$(app_setting ENABLE_HARDENED_RUNTIME)"
enable_app_sandbox="$(app_setting ENABLE_APP_SANDBOX)"

share_product_bundle_identifier="$(share_setting PRODUCT_BUNDLE_IDENTIFIER)"
share_code_sign_style="$(share_setting CODE_SIGN_STYLE)"
share_enable_hardened_runtime="$(share_setting ENABLE_HARDENED_RUNTIME)"
share_enable_app_sandbox="$(share_setting ENABLE_APP_SANDBOX)"
share_extension_api_only="$(share_setting APPLICATION_EXTENSION_API_ONLY)"
share_skip_install="$(share_setting SKIP_INSTALL)"

[ "$code_sign_style" = "Automatic" ] || fail "main app CODE_SIGN_STYLE must stay Automatic, got $code_sign_style"
[ "$enable_hardened_runtime" = "YES" ] || fail "main app ENABLE_HARDENED_RUNTIME must stay YES"
[ "$enable_app_sandbox" = "YES" ] || fail "main app ENABLE_APP_SANDBOX must stay YES"
[ "$share_code_sign_style" = "Automatic" ] || fail "share extension CODE_SIGN_STYLE must stay Automatic, got $share_code_sign_style"
[ "$share_enable_hardened_runtime" = "YES" ] || fail "share extension ENABLE_HARDENED_RUNTIME must stay YES"
[ "$share_enable_app_sandbox" = "YES" ] || fail "share extension ENABLE_APP_SANDBOX must stay YES"
[ "$share_extension_api_only" = "YES" ] || fail "share extension must keep APPLICATION_EXTENSION_API_ONLY=YES"
[ "$share_skip_install" = "YES" ] || fail "share extension must keep SKIP_INSTALL=YES"

if [ "$env_name" = "prod" ]; then
  [ "$product_bundle_identifier" = "com.avalsys.autonomoav.mac" ] || fail "prod bundle must be com.avalsys.autonomoav.mac"
  [ "$autonomo_bundle_identifier" = "com.avalsys.autonomoav.mac" ] || fail "prod AUTONOMOAV_MACOS_BUNDLE_IDENTIFIER must be com.avalsys.autonomoav.mac"
  [ "$app_group_identifier" = "group.com.avalsys.autonomoav" ] || fail "prod app group mismatch"
  [ "$config_environment" = "prod" ] || fail "prod AUTONOMOAV_CONFIG_ENVIRONMENT must be prod"
  [ "$development_team" = "935PM55U6R" ] || fail "prod development team must be 935PM55U6R"
  [ "$keychain_service" = "com.avalsys.autonomoav.mac.account.v2" ] || fail "prod ACCOUNTAV_KEYCHAIN_SERVICE mismatch"
  [ "$keychain_access_group" = "935PM55U6R.com.avalsys.autonomoav.mac" ] || fail "prod ACCOUNTAV_KEYCHAIN_ACCESS_GROUP mismatch"
  [ "$share_product_bundle_identifier" = "com.avalsys.autonomoav.mac.share" ] || fail "prod share extension bundle mismatch"
  require_present "ACCOUNTAV_PUBLISHABLE_KEY" "$publishable_key"
  require_present "ACCOUNTAV_API_BASE_URL" "$api_base_url"
  require_present "AUTONOMOAV_API_BASE_URL" "$autonomo_api_base_url"
  require_present "ACCOUNTAV_MANAGEMENT_URL" "$management_url"
  require_present "AUTONOMOAV_DELETE_ACCOUNT_URL" "$delete_account_url"
  require_present "AUTONOMOAV_TERMS_URL" "$terms_url"
  require_present "AUTONOMOAV_PRIVACY_URL" "$privacy_url"
  require_present "AUTONOMOAV_MACOS_SENTRY_DSN" "$autonomoav_macos_sentry_dsn"
  require_present "SUPPORT_EMAIL_TO" "$support_email"
  [[ "$publishable_key" == pk_live_* ]] || fail "prod publishable key must be pk_live"
  if printf '%s\n%s\n%s\n%s\n%s\n' "$product_bundle_identifier" "$api_base_url" "$autonomo_api_base_url" "$management_url" "$support_base_url" | rg -q 'preview|127\.0\.0\.1|localhost|\.dev'; then
    fail "prod settings contain preview/local/dev values"
  fi
else
  [ "$product_bundle_identifier" = "com.avalsys.autonomoav.mac.dev" ] || fail "dev bundle must be com.avalsys.autonomoav.mac.dev"
  [ "$autonomo_bundle_identifier" = "com.avalsys.autonomoav.mac.dev" ] || fail "dev AUTONOMOAV_MACOS_BUNDLE_IDENTIFIER must be com.avalsys.autonomoav.mac.dev"
  [ "$app_group_identifier" = "group.com.avalsys.autonomoav.dev" ] || fail "dev app group mismatch"
  [ "$config_environment" = "dev" ] || fail "dev AUTONOMOAV_CONFIG_ENVIRONMENT must be dev"
  [ "$keychain_service" = "com.avalsys.autonomoav.mac.dev.account.v2" ] || fail "dev ACCOUNTAV_KEYCHAIN_SERVICE mismatch"
  [ "$keychain_access_group" = "935PM55U6R.com.avalsys.autonomoav.mac.dev" ] || fail "dev ACCOUNTAV_KEYCHAIN_ACCESS_GROUP mismatch"
  [ "$share_product_bundle_identifier" = "com.avalsys.autonomoav.mac.dev.share" ] || fail "dev share extension bundle mismatch"
  if ! is_missing "$publishable_key"; then
    [[ "$publishable_key" == pk_test_* || "$publishable_key" == pk_live_* ]] || fail "dev publishable key has unexpected prefix"
  fi
fi

allow_https_or_dev_local_url ACCOUNTAV_API_BASE_URL "$api_base_url"
allow_https_or_dev_local_url AUTONOMOAV_API_BASE_URL "$autonomo_api_base_url"
allow_https_or_dev_local_url ACCOUNTAV_MANAGEMENT_URL "$management_url"

for item in \
  "AUTONOMOAV_DELETE_ACCOUNT_URL:$delete_account_url" \
  "AUTONOMOAV_TERMS_URL:$terms_url" \
  "AUTONOMOAV_PRIVACY_URL:$privacy_url"; do
  name="${item%%:*}"
  value="${item#*:}"
  if is_missing "$value"; then
    [ "$env_name" = "prod" ] && fail "$name must resolve to a real value for prod"
  else
    [[ "$value" == https://* ]] || fail "$name did not resolve as https://*: $value"
  fi
done

if ! is_missing "$support_base_url"; then
  [[ "$support_base_url" == https://* ]] || fail "SUPPORTAV_BASE_URL did not resolve as https://*: $support_base_url"
fi
if ! is_missing "$support_email"; then
  [[ "$support_email" == *"@"* ]] || fail "SUPPORT_EMAIL_TO must look like an email address"
fi
if ! is_missing "$autonomoav_macos_sentry_dsn"; then
  [[ "$autonomoav_macos_sentry_dsn" == https://*@*/[0-9]* ]] || fail "AUTONOMOAV_MACOS_SENTRY_DSN must look like a Sentry DSN"
fi

redacted_key="$publishable_key"
if ! is_missing "$publishable_key"; then
  redacted_key="${publishable_key:0:8}...${#publishable_key}"
fi
sentry_status="$autonomoav_macos_sentry_dsn"
if ! is_missing "$autonomoav_macos_sentry_dsn"; then
  sentry_status="configured:${#autonomoav_macos_sentry_dsn}"
fi

cat <<EOF
Autonomo AV macOS runtime config ($env_name)
  configuration: $configuration
  product bundle: $product_bundle_identifier
  share bundle: $share_product_bundle_identifier
  app group: $app_group_identifier
  environment: $config_environment
  development team: ${development_team:-unknown}
  code sign style: $code_sign_style
  App Sandbox: $enable_app_sandbox
  Hardened Runtime: $enable_hardened_runtime
  Account AV API: $api_base_url
  Autonomo AV API: $autonomo_api_base_url
  Account AV management: $management_url
  Account AV keychain service: $keychain_service
  Account AV keychain access group: $keychain_access_group
  Support AV: ${support_base_url:-email fallback}
  support email: ${support_email:-unset}
  publishable key: $redacted_key
  Sentry DSN: $sentry_status
EOF

if [ "$failures" -gt 0 ]; then
  exit 1
fi

echo "Runtime config check passed."
