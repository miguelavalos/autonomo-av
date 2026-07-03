#!/usr/bin/env bash
set -euo pipefail

macos_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
product_root="$(cd "$macos_root/../.." && pwd)"
workspace_root="$(cd "$product_root/../.." && pwd)"
suite_root="${AVALSYS_SUITE_DIR:-$workspace_root/private/avalsys-suite}"
output_path="$macos_root/Config/Local.xcconfig"
env_name=""
stdout_only=0

usage() {
  cat <<'USAGE'
Usage:
  scripts/generate-macos-local-xcconfig.sh --env dev|prod [--stdout]

Generates Config/Local.xcconfig from environment variables and, when
available, private suite Varlock values. The output is gitignored.
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --env)
      env_name="${2:-}"
      shift 2
      ;;
    --stdout)
      stdout_only=1
      shift
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

profile="local"
bundle_identifier="com.avalsys.autonomoav.mac.dev"
app_group_identifier="group.com.avalsys.autonomoav.dev"
if [ "$env_name" = "prod" ]; then
  profile="production"
  bundle_identifier="com.avalsys.autonomoav.mac"
  app_group_identifier="group.com.avalsys.autonomoav"
fi

varlock_bin="$suite_root/node_modules/.bin/varlock"
if [ -x "$varlock_bin" ] && [ -x "$suite_root/scripts/resolve-infisical-bootstrap-env.sh" ]; then
  eval "$("$suite_root/scripts/resolve-infisical-bootstrap-env.sh" "$profile")"
fi

read_optional_config() {
  local name="$1"
  local value="${!name:-}"
  if [ -n "$value" ]; then
    printf '%s' "$value"
    return 0
  fi
  if [ -x "$varlock_bin" ]; then
    value="$("$varlock_bin" printenv --path "$suite_root/services/api" "$name" 2>/dev/null || true)"
    if [ -n "$value" ]; then
      printf '%s' "$value"
      return 0
    fi
  fi
  if [ -x "$suite_root/scripts/resolve-infisical-optional-secret.sh" ]; then
    "$suite_root/scripts/resolve-infisical-optional-secret.sh" "$profile" "$name" 2>/dev/null || true
  fi
}

normalize_optional_xcconfig_value() {
  local value="$1"
  if [ -n "$value" ]; then
    printf '%s' "$value"
  else
    printf '%s' "\$(inherited)"
  fi
}

read_account_publishable_key() {
  local value="${ACCOUNTAV_PUBLISHABLE_KEY:-${VITE_ACCOUNTAV_PUBLISHABLE_KEY:-}}"
  if [ -n "$value" ]; then
    printf '%s' "$value"
    return 0
  fi
  if [ -x "$varlock_bin" ]; then
    "$varlock_bin" printenv --path "$suite_root/apps/account-av" VITE_ACCOUNTAV_PUBLISHABLE_KEY 2>/dev/null || true
  fi
}

read_account_api_base_url() {
  local value="${ACCOUNTAV_API_BASE_URL:-${VITE_ACCOUNTAV_API_BASE_URL:-}}"
  if [ -n "$value" ]; then
    printf '%s' "$value"
    return 0
  fi
  value="$(read_optional_config ACCOUNTAV_API_BASE_URL)"
  if [ -n "$value" ]; then
    printf '%s' "$value"
    return 0
  fi
  if [ -x "$varlock_bin" ]; then
    "$varlock_bin" printenv --path "$suite_root/apps/account-av" VITE_ACCOUNTAV_API_BASE_URL 2>/dev/null || true
  fi
}

escape_xcconfig_url() {
  printf '%s' "$1" | sed 's#/#$(XCCONFIG_SLASH)#g'
}

publishable_key="$(read_account_publishable_key)"
api_base_url="$(read_account_api_base_url)"
autonomo_api_base_url="${AUTONOMOAV_API_BASE_URL:-$api_base_url}"
management_url="$(read_optional_config ACCOUNTAV_MANAGEMENT_URL)"
development_team="$(read_optional_config AVALSYS_APPLE_DEVELOPMENT_TEAM)"
support_email="${SUPPORT_EMAIL_TO:-support@avalsys.com}"
support_base_url="${SUPPORTAV_BASE_URL:-https://support-av.avalsys.com}"
keychain_service="$(read_optional_config ACCOUNTAV_KEYCHAIN_SERVICE)"
keychain_access_group="$(read_optional_config ACCOUNTAV_KEYCHAIN_ACCESS_GROUP)"
autonomoav_macos_sentry_dsn="$(read_optional_config AUTONOMOAV_MACOS_SENTRY_DSN)"

if [ "$env_name" = "dev" ]; then
  case "$api_base_url" in
    ""|http://127.0.0.1*|http://localhost*)
      api_base_url="https://api-account-av-preview.avalsys.com"
      ;;
  esac
  case "$autonomo_api_base_url" in
    ""|http://127.0.0.1*|http://localhost*)
      autonomo_api_base_url="$api_base_url"
      ;;
  esac
fi

if [ -z "$development_team" ] && [ "$env_name" = "prod" ]; then
  development_team="935PM55U6R"
elif [ -z "$development_team" ]; then
  development_team="\$(inherited)"
fi
if [ "$development_team" = "346677S99H" ]; then
  echo "Warning: replacing stale non-Avalsys Apple team 346677S99H with 935PM55U6R." >&2
  development_team="935PM55U6R"
fi
if [ -z "$keychain_service" ] || [ "$keychain_service" = "\$(inherited)" ]; then
  keychain_service="$bundle_identifier.account.v2"
fi
if [ -z "$keychain_access_group" ] || [ "$keychain_access_group" = "\$(inherited)" ]; then
  keychain_access_group="935PM55U6R.$bundle_identifier"
fi
if [ -z "$management_url" ] && [ -n "$api_base_url" ]; then
  management_url="$api_base_url"
fi

allow_https_or_dev_local_url() {
  local name="$1"
  local value="$2"

  if [ -z "$value" ]; then
    if [ "$env_name" = "prod" ]; then
      echo "$name is required for prod." >&2
      exit 1
    fi
    return 0
  fi

  case "$value" in
    https://*) return 0 ;;
  esac

  if [ "$env_name" = "dev" ]; then
    case "$value" in
      http://127.0.0.1:*|http://localhost:*) return 0 ;;
    esac
  fi

  echo "$name must use HTTPS unless it is a dev localhost URL." >&2
  exit 1
}

if [ "$env_name" = "prod" ]; then
  if [ -z "$publishable_key" ]; then
    echo "ACCOUNTAV_PUBLISHABLE_KEY is required for prod." >&2
    exit 1
  fi
  if [ -z "$autonomoav_macos_sentry_dsn" ]; then
    echo "AUTONOMOAV_MACOS_SENTRY_DSN is required for prod." >&2
    exit 1
  fi
  if [[ "$publishable_key" != pk_live_* ]]; then
    echo "Production ACCOUNTAV_PUBLISHABLE_KEY must start with pk_live_." >&2
    exit 1
  fi
fi

if [ -n "$publishable_key" ]; then
  case "$publishable_key" in
    pk_test_*|pk_live_*) ;;
    *) echo "ACCOUNTAV_PUBLISHABLE_KEY must start with pk_test_ or pk_live_." >&2; exit 1 ;;
  esac
fi

allow_https_or_dev_local_url ACCOUNTAV_API_BASE_URL "$api_base_url"
allow_https_or_dev_local_url AUTONOMOAV_API_BASE_URL "$autonomo_api_base_url"
allow_https_or_dev_local_url ACCOUNTAV_MANAGEMENT_URL "$management_url"
case "$support_base_url" in
  https://*) ;;
  *) echo "SUPPORTAV_BASE_URL must use HTTPS." >&2; exit 1 ;;
esac
case "$support_email" in
  *@*) ;;
  *) echo "SUPPORT_EMAIL_TO must look like an email address." >&2; exit 1 ;;
esac

for value in "$api_base_url" "$autonomo_api_base_url" "$management_url"; do
  if [ "$env_name" = "prod" ] && printf '%s' "$value" | rg -q '127\.0\.0\.1|localhost|preview|\.dev'; then
    echo "Production API/runtime URLs must not contain local, preview, or .dev values." >&2
    exit 1
  fi
done

publishable_key="$(normalize_optional_xcconfig_value "$publishable_key")"
autonomoav_macos_sentry_dsn="$(normalize_optional_xcconfig_value "$autonomoav_macos_sentry_dsn")"

generated_at="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
content="$(cat <<EOF
// GENERATED by scripts/generate-macos-local-xcconfig.sh --env $env_name
// Generated at $generated_at
// Do not edit manually. Regenerate when switching dev/prod.
XCCONFIG_SLASH = /
AUTONOMOAV_CONFIG_ENVIRONMENT = $env_name
AUTONOMOAV_MACOS_BUNDLE_IDENTIFIER = $bundle_identifier
AUTONOMOAV_APP_GROUP_IDENTIFIER = $app_group_identifier
AVALSYS_APPLE_DEVELOPMENT_TEAM = $development_team
ACCOUNTAV_PUBLISHABLE_KEY = $publishable_key
ACCOUNTAV_KEYCHAIN_SERVICE = $keychain_service
ACCOUNTAV_KEYCHAIN_ACCESS_GROUP = $keychain_access_group
SUPPORT_EMAIL_TO = $support_email
SUPPORTAV_BASE_URL = $(escape_xcconfig_url "$support_base_url")
ACCOUNTAV_API_BASE_URL = $(escape_xcconfig_url "$api_base_url")
AUTONOMOAV_API_BASE_URL = $(escape_xcconfig_url "$autonomo_api_base_url")
ACCOUNTAV_MANAGEMENT_URL = $(escape_xcconfig_url "$management_url")
AUTONOMOAV_DELETE_ACCOUNT_URL = $(escape_xcconfig_url "https://autonomo-av.avalsys.com/delete-account")
AUTONOMOAV_TERMS_URL = $(escape_xcconfig_url "https://autonomo-av.avalsys.com/terms")
AUTONOMOAV_PRIVACY_URL = $(escape_xcconfig_url "https://autonomo-av.avalsys.com/privacy")
AUTONOMOAV_MACOS_SENTRY_DSN = $(escape_xcconfig_url "$autonomoav_macos_sentry_dsn")
EOF
)"

if [ "$stdout_only" -eq 1 ]; then
  printf '%s\n' "$content"
else
  umask 077
  mkdir -p "$(dirname "$output_path")"
  printf '%s\n' "$content" > "$output_path"
  echo "Generated $output_path for $env_name."
fi
