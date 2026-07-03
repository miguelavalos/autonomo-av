#!/usr/bin/env bash
set -euo pipefail

ios_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
env_name=""
configuration="Debug"
destination_args=(-destination "generic/platform=iOS")

usage() {
  cat <<'USAGE'
Usage:
  scripts/check-ios-runtime-config.sh --env dev|prod [--configuration Debug|Release]

Validates effective Autonomo AV iOS build settings without printing secrets.
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

settings_file="$(mktemp)"
trap 'rm -f "$settings_file"' EXIT

xcodebuild \
  -project "$ios_root/AutonomoAV.xcodeproj" \
  -scheme AutonomoAV \
  -configuration "$configuration" \
  "${destination_args[@]}" \
  -showBuildSettings > "$settings_file"

setting() {
  local key="$1"
  awk -F= -v wanted="$key" '
    $1 ~ "^[[:space:]]*" wanted "[[:space:]]*$" {
      value=$2
      sub(/^[[:space:]]+/, "", value)
      sub(/[[:space:]]+$/, "", value)
      print value
      exit
    }
  ' "$settings_file"
}

failures=0
fail() {
  printf 'FAIL %s\n' "$1" >&2
  failures=$((failures + 1))
}

require_present() {
  local label="$1"
  local value="$2"
  if [ -z "$value" ] || [ "$value" = "\$(inherited)" ]; then
    fail "$label must resolve to a real value"
  fi
}

product_bundle_identifier="$(setting PRODUCT_BUNDLE_IDENTIFIER)"
autonomo_bundle_identifier="$(setting AUTONOMOAV_BUNDLE_IDENTIFIER)"
app_group_identifier="$(setting AUTONOMOAV_APP_GROUP_IDENTIFIER)"
api_base_url="$(setting ACCOUNTAV_API_BASE_URL)"
autonomo_api_base_url="$(setting AUTONOMOAV_API_BASE_URL)"
publishable_key="$(setting ACCOUNTAV_PUBLISHABLE_KEY)"
keychain_access_group="$(setting ACCOUNTAV_KEYCHAIN_ACCESS_GROUP)"
revenuecat_public_api_key="$(setting AUTONOMOAV_REVENUECAT_PUBLIC_API_KEY)"
revenuecat_offering_id="$(setting AUTONOMOAV_REVENUECAT_OFFERING_ID)"
revenuecat_monthly_package_id="$(setting AUTONOMOAV_REVENUECAT_MONTHLY_PACKAGE_ID)"
autonomoav_ios_sentry_dsn="$(setting AUTONOMOAV_IOS_SENTRY_DSN)"
debug_force_pro_mode="$(setting AUTONOMOAV_DEBUG_FORCE_PRO_MODE)"
development_team="$(setting DEVELOPMENT_TEAM)"
debug_force_pro_mode_normalized="$(printf '%s' "$debug_force_pro_mode" | tr '[:upper:]' '[:lower:]')"
debug_force_pro_mode_enabled=0

case "$debug_force_pro_mode_normalized" in
  1|true|yes|on|enabled)
    debug_force_pro_mode_enabled=1
    ;;
esac

if [ "$env_name" = "prod" ]; then
  require_present "AUTONOMOAV_REVENUECAT_PUBLIC_API_KEY" "$revenuecat_public_api_key"
  require_present "AUTONOMOAV_REVENUECAT_OFFERING_ID" "$revenuecat_offering_id"
  require_present "AUTONOMOAV_REVENUECAT_MONTHLY_PACKAGE_ID" "$revenuecat_monthly_package_id"
  require_present "AUTONOMOAV_IOS_SENTRY_DSN" "$autonomoav_ios_sentry_dsn"
  [ "$product_bundle_identifier" = "com.avalsys.autonomoav" ] || fail "prod bundle must be com.avalsys.autonomoav"
  [ "$autonomo_bundle_identifier" = "com.avalsys.autonomoav" ] || fail "prod AUTONOMOAV_BUNDLE_IDENTIFIER must be com.avalsys.autonomoav"
  [ "$app_group_identifier" = "group.com.avalsys.autonomoav" ] || fail "prod app group mismatch"
  [ "$development_team" = "935PM55U6R" ] || fail "prod development team must be 935PM55U6R"
  [ "$keychain_access_group" = "935PM55U6R.com.avalsys.autonomoav" ] || fail "prod keychain access group mismatch"
  [[ "$publishable_key" == pk_live_* ]] || fail "prod publishable key must be pk_live"
  [ "$debug_force_pro_mode_enabled" -eq 0 ] || fail "prod AUTONOMOAV_DEBUG_FORCE_PRO_MODE must be disabled"
else
  [ "$product_bundle_identifier" = "com.avalsys.autonomoav.dev" ] || fail "dev bundle must be com.avalsys.autonomoav.dev"
  [ "$autonomo_bundle_identifier" = "com.avalsys.autonomoav.dev" ] || fail "dev AUTONOMOAV_BUNDLE_IDENTIFIER must be com.avalsys.autonomoav.dev"
  [ "$app_group_identifier" = "group.com.avalsys.autonomoav.dev" ] || fail "dev app group mismatch"
  [ "$keychain_access_group" = "935PM55U6R.com.avalsys.autonomoav.dev" ] || fail "dev keychain access group mismatch"
  if [ -n "$publishable_key" ] && [ "$publishable_key" != '$(inherited)' ]; then
    [[ "$publishable_key" == pk_test_* || "$publishable_key" == pk_live_* ]] || fail "dev publishable key has unexpected prefix"
  fi
fi

if [ -n "$revenuecat_public_api_key" ] && [ "$revenuecat_public_api_key" != '$(inherited)' ]; then
  [[ "$revenuecat_public_api_key" == appl_* ]] || fail "AUTONOMOAV_REVENUECAT_PUBLIC_API_KEY must use the RevenueCat public appl_ prefix"
  [[ "$revenuecat_public_api_key" != sk_* ]] || fail "AUTONOMOAV_REVENUECAT_PUBLIC_API_KEY must not be a RevenueCat secret key"
fi
if [ -n "$revenuecat_offering_id" ] && [ "$revenuecat_offering_id" != '$(inherited)' ]; then
  [ "$revenuecat_offering_id" = "default" ] || fail "AUTONOMOAV_REVENUECAT_OFFERING_ID must be default, got $revenuecat_offering_id"
fi
if [ -n "$revenuecat_monthly_package_id" ] && [ "$revenuecat_monthly_package_id" != '$(inherited)' ]; then
  [ "$revenuecat_monthly_package_id" = '$rc_monthly' ] || fail "AUTONOMOAV_REVENUECAT_MONTHLY_PACKAGE_ID must be literal \$rc_monthly, got $revenuecat_monthly_package_id"
fi
if [ -n "$autonomoav_ios_sentry_dsn" ] && [ "$autonomoav_ios_sentry_dsn" != '$(inherited)' ]; then
  [[ "$autonomoav_ios_sentry_dsn" == https://*@*/[0-9]* ]] || fail "AUTONOMOAV_IOS_SENTRY_DSN must look like a Sentry DSN"
fi

for url in "$api_base_url" "$autonomo_api_base_url"; do
  if [ -n "$url" ] && [ "$url" != '$(inherited)' ]; then
    [[ "$url" == https://* ]] || fail "API URL must resolve to https://*: $url"
  fi
done

redacted_key=""
if [ -n "$publishable_key" ] && [ "$publishable_key" != '$(inherited)' ]; then
  redacted_key="${publishable_key:0:8}...${#publishable_key}"
else
  redacted_key="$publishable_key"
fi
redacted_revenuecat_key="$revenuecat_public_api_key"
if [ -n "$revenuecat_public_api_key" ] && [ "$revenuecat_public_api_key" != '$(inherited)' ]; then
  redacted_revenuecat_key="${revenuecat_public_api_key:0:8}...${#revenuecat_public_api_key}"
fi
sentry_status="$autonomoav_ios_sentry_dsn"
if [ -n "$autonomoav_ios_sentry_dsn" ] && [ "$autonomoav_ios_sentry_dsn" != '$(inherited)' ]; then
  sentry_status="configured:${#autonomoav_ios_sentry_dsn}"
fi

cat <<EOF
Autonomo AV iOS runtime config ($env_name)
  configuration: $configuration
  product bundle: $product_bundle_identifier
  autonomo bundle: $autonomo_bundle_identifier
  app group: $app_group_identifier
  development team: ${development_team:-unknown}
  Account AV API: $api_base_url
  Autonomo AV API: $autonomo_api_base_url
  Account AV keychain access group: $keychain_access_group
  publishable key: $redacted_key
  RevenueCat key: $redacted_revenuecat_key
  RevenueCat offering: $revenuecat_offering_id
  RevenueCat monthly package: $revenuecat_monthly_package_id
  Sentry DSN: $sentry_status
  debug force Pro mode: ${debug_force_pro_mode:-unset}
EOF

if [ "$failures" -gt 0 ]; then
  exit 1
fi

echo "Runtime config check passed."
