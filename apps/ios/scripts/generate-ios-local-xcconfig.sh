#!/usr/bin/env bash
set -euo pipefail

ios_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
product_root="$(cd "$ios_root/../.." && pwd)"
workspace_root="$(cd "$product_root/../.." && pwd)"
suite_root="${AVALSYS_SUITE_DIR:-$workspace_root/private/avalsys-suite}"
output_path="$ios_root/Config/Local.xcconfig"
env_name=""
stdout_only=0

usage() {
  cat <<'USAGE'
Usage:
  scripts/generate-ios-local-xcconfig.sh --env dev|prod [--stdout]

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
bundle_identifier="com.avalsys.autonomoav.dev"
if [ "$env_name" = "prod" ]; then
  profile="production"
  bundle_identifier="com.avalsys.autonomoav"
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
    "$varlock_bin" printenv --path "$suite_root/services/api" "$name" 2>/dev/null || true
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
revenuecat_public_api_key="$(read_optional_config AUTONOMOAV_REVENUECAT_PUBLIC_API_KEY)"
revenuecat_offering_id="$(read_optional_config AUTONOMOAV_REVENUECAT_OFFERING_ID)"
revenuecat_monthly_package_id="$(read_optional_config AUTONOMOAV_REVENUECAT_MONTHLY_PACKAGE_ID)"

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
if [ -z "$keychain_access_group" ] || [ "$keychain_access_group" = "\$(inherited)" ]; then
  keychain_access_group="935PM55U6R.$bundle_identifier"
fi
if [ -z "$management_url" ] && [ -n "$api_base_url" ]; then
  management_url="$api_base_url"
fi

if [ "$env_name" = "prod" ]; then
  if [ -z "$revenuecat_public_api_key" ]; then
    echo "AUTONOMOAV_REVENUECAT_PUBLIC_API_KEY is required for prod." >&2
    exit 1
  fi
  if [ -z "$revenuecat_offering_id" ]; then
    echo "AUTONOMOAV_REVENUECAT_OFFERING_ID is required for prod." >&2
    exit 1
  fi
  if [ -z "$revenuecat_monthly_package_id" ]; then
    echo "AUTONOMOAV_REVENUECAT_MONTHLY_PACKAGE_ID is required for prod." >&2
    exit 1
  fi
fi

if [ -n "$revenuecat_public_api_key" ]; then
  case "$revenuecat_public_api_key" in
    appl_*) ;;
    sk_*) echo "AUTONOMOAV_REVENUECAT_PUBLIC_API_KEY must not be a RevenueCat secret key." >&2; exit 1 ;;
    *) echo "AUTONOMOAV_REVENUECAT_PUBLIC_API_KEY must start with appl_." >&2; exit 1 ;;
  esac
fi

revenuecat_public_api_key="$(normalize_optional_xcconfig_value "$revenuecat_public_api_key")"
revenuecat_offering_id="$(normalize_optional_xcconfig_value "$revenuecat_offering_id")"
revenuecat_monthly_package_id="$(normalize_optional_xcconfig_value "$revenuecat_monthly_package_id")"

generated_at="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
content="$(cat <<EOF
// GENERATED by scripts/generate-ios-local-xcconfig.sh --env $env_name
// Generated at $generated_at
// Do not edit manually. Regenerate when switching dev/prod.
XCCONFIG_SLASH = /
AUTONOMOAV_CONFIG_ENVIRONMENT = $env_name
AUTONOMOAV_BUNDLE_IDENTIFIER = $bundle_identifier
AUTONOMOAV_APP_GROUP_IDENTIFIER = group.$bundle_identifier
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
AUTONOMOAV_REVENUECAT_PUBLIC_API_KEY = $revenuecat_public_api_key
AUTONOMOAV_REVENUECAT_OFFERING_ID = $revenuecat_offering_id
AUTONOMOAV_REVENUECAT_MONTHLY_PACKAGE_ID = $revenuecat_monthly_package_id
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
