#!/usr/bin/env bash
set -euo pipefail

app_path=""
env_name="dev"
team_id="935PM55U6R"

usage() {
  cat <<'USAGE'
Usage:
  scripts/check-macos-signed-build.sh --app <path-to-Autonomo AV.app> [--env dev|prod]

Validates a built Autonomo AV macOS app bundle for local signed QA without
archiving, exporting, uploading, or contacting App Store Connect.
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --app)
      app_path="${2:-}"
      shift 2
      ;;
    --env)
      env_name="${2:-}"
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

if [ -z "$app_path" ]; then
  echo "--app is required." >&2
  usage >&2
  exit 2
fi
if [ "$env_name" != "dev" ] && [ "$env_name" != "prod" ]; then
  echo "--env must be dev or prod." >&2
  exit 2
fi

if [ "$env_name" = "prod" ]; then
  app_bundle_id="com.avalsys.autonomoav.mac"
  app_group_id="group.com.avalsys.autonomoav"
else
  app_bundle_id="com.avalsys.autonomoav.mac.dev"
  app_group_id="group.com.avalsys.autonomoav.dev"
fi
share_bundle_id="$app_bundle_id.share"
expected_keychain_access_group="$team_id.$app_bundle_id"
expected_keychain_service="$app_bundle_id.account.v2"
share_path="$app_path/Contents/PlugIns/Autonomo AV Inbox.appex"

failures=0
fail() {
  printf 'FAIL %s\n' "$1" >&2
  failures=$((failures + 1))
}

plist_print() {
  /usr/libexec/PlistBuddy -c "Print :$2" "$1" 2>/dev/null || true
}

require_equal() {
  local label="$1"
  local expected="$2"
  local actual="$3"
  if [ "$actual" != "$expected" ]; then
    fail "$label must be $expected, got ${actual:-<missing>}"
  fi
}

require_true() {
  local label="$1"
  local actual="$2"
  if [ "$actual" != "true" ]; then
    fail "$label must be true, got ${actual:-<missing>}"
  fi
}

require_array_contains() {
  local label="$1"
  local file="$2"
  local key="$3"
  local expected="$4"
  local values
  values="$(plist_print "$file" "$key")"
  if ! printf '%s' "$values" | grep -Fq "$expected"; then
    fail "$label must include $expected"
  fi
}

require_array_absent() {
  local label="$1"
  local file="$2"
  local key="$3"
  local unexpected="$4"
  local values
  values="$(plist_print "$file" "$key")"
  if printf '%s' "$values" | grep -Fq "$unexpected"; then
    fail "$label must not include $unexpected"
  fi
}

signed_info() {
  codesign -dv --verbose=4 "$1" 2>&1 || true
}

signed_value() {
  local output="$1"
  local key="$2"
  printf '%s\n' "$output" | awk -F= -v wanted="$key" '$1 == wanted { print $2; exit }'
}

validate_code_signature() {
  local bundle_path="$1"
  local label="$2"
  local expected_identifier="$3"
  local output
  output="$(signed_info "$bundle_path")"

  require_equal "$label signing identifier" "$expected_identifier" "$(signed_value "$output" Identifier)"
  require_equal "$label signing team" "$team_id" "$(signed_value "$output" TeamIdentifier)"
  if ! printf '%s\n' "$output" | grep -Fq "Runtime Version="; then
    fail "$label must be signed with hardened runtime"
  fi
}

validate_entitlements() {
  local bundle_path="$1"
  local label="$2"
  local expected_identifier="$3"
  local requires_keychain="$4"
  local requires_network="$5"
  local requires_user_selected_read_only="$6"
  local entitlements_file

  entitlements_file="$(mktemp)"
  codesign -d --entitlements :- "$bundle_path" > "$entitlements_file" 2>/dev/null || true

  require_equal "$label application identifier" "$team_id.$expected_identifier" "$(plist_print "$entitlements_file" "com.apple.application-identifier")"
  require_equal "$label team entitlement" "$team_id" "$(plist_print "$entitlements_file" "com.apple.developer.team-identifier")"
  require_true "$label app sandbox entitlement" "$(plist_print "$entitlements_file" "com.apple.security.app-sandbox")"
  require_array_contains "$label app group entitlement" "$entitlements_file" "com.apple.security.application-groups" "$app_group_id"

  if [ "$requires_keychain" = "yes" ]; then
    require_array_contains "$label keychain entitlement" "$entitlements_file" "keychain-access-groups" "$expected_keychain_access_group"
  else
    require_array_absent "$label keychain entitlement" "$entitlements_file" "keychain-access-groups" "$expected_keychain_access_group"
  fi

  if [ "$requires_network" = "yes" ]; then
    require_true "$label network client entitlement" "$(plist_print "$entitlements_file" "com.apple.security.network.client")"
  elif [ "$(plist_print "$entitlements_file" "com.apple.security.network.client")" = "true" ]; then
    fail "$label must not have network client entitlement"
  fi

  if [ "$requires_user_selected_read_only" = "yes" ]; then
    require_true "$label user-selected read-only file entitlement" "$(plist_print "$entitlements_file" "com.apple.security.files.user-selected.read-only")"
  elif [ "$(plist_print "$entitlements_file" "com.apple.security.files.user-selected.read-only")" = "true" ]; then
    fail "$label must not have user-selected read-only file entitlement"
  fi

  rm -f "$entitlements_file"
}

profile_summary() {
  local bundle_path="$1"
  local label="$2"
  local expected_identifier="$3"
  local profile_path="$bundle_path/Contents/embedded.provisionprofile"
  local profile_file
  local name
  local application_identifier
  local app_id_status
  local groups
  local app_group_proof

  if [ ! -f "$profile_path" ]; then
    printf '  %s profile: missing\n' "$label"
    return
  fi

  profile_file="$(mktemp)"
  if ! security cms -D -i "$profile_path" > "$profile_file" 2>/dev/null; then
    rm -f "$profile_file"
    printf '  %s profile: unreadable\n' "$label"
    return
  fi

  name="$(plist_print "$profile_file" Name)"
  application_identifier="$(plist_print "$profile_file" "Entitlements:com.apple.application-identifier")"
  groups="$(plist_print "$profile_file" "Entitlements:com.apple.security.application-groups")"
  rm -f "$profile_file"

  app_id_status="unexpected"
  if [ "$application_identifier" = "$team_id.$expected_identifier" ]; then
    app_id_status="app-specific"
  elif [ "$application_identifier" = "$team_id.*" ]; then
    app_id_status="wildcard"
  fi

  app_group_proof="no"
  if printf '%s' "$groups" | grep -Fq "$app_group_id"; then
    app_group_proof="yes"
  fi

  printf '  %s profile: %s (%s, %s, app-group-proof=%s)\n' \
    "$label" "${name:-unknown}" "${application_identifier:-missing}" "$app_id_status" "$app_group_proof"
}

if [ ! -d "$app_path" ]; then
  echo "App bundle not found: $app_path" >&2
  exit 1
fi
if [ ! -d "$share_path" ]; then
  fail "missing embedded share extension at $share_path"
fi

app_info="$app_path/Contents/Info.plist"
share_info="$share_path/Contents/Info.plist"

require_equal "app bundle identifier" "$app_bundle_id" "$(plist_print "$app_info" CFBundleIdentifier)"
require_equal "app Account AV keychain service" "$expected_keychain_service" "$(plist_print "$app_info" ACCOUNTAV_KEYCHAIN_SERVICE)"
require_equal "app Account AV keychain access group" "$expected_keychain_access_group" "$(plist_print "$app_info" ACCOUNTAV_KEYCHAIN_ACCESS_GROUP)"
require_equal "app group config" "$app_group_id" "$(plist_print "$app_info" AUTONOMOAV_APP_GROUP_IDENTIFIER)"

if [ -d "$share_path" ]; then
  require_equal "share extension bundle identifier" "$share_bundle_id" "$(plist_print "$share_info" CFBundleIdentifier)"
  require_equal "share extension app group config" "$app_group_id" "$(plist_print "$share_info" AUTONOMOAV_APP_GROUP_IDENTIFIER)"
fi

validate_code_signature "$app_path" "main app" "$app_bundle_id"
validate_entitlements "$app_path" "main app" "$app_bundle_id" yes yes yes

if [ -d "$share_path" ]; then
  validate_code_signature "$share_path" "share extension" "$share_bundle_id"
  validate_entitlements "$share_path" "share extension" "$share_bundle_id" no no no
fi

app_get_task_allow_file="$(mktemp)"
codesign -d --entitlements :- "$app_path" > "$app_get_task_allow_file" 2>/dev/null || true
get_task_allow="$(plist_print "$app_get_task_allow_file" "com.apple.security.get-task-allow")"
rm -f "$app_get_task_allow_file"

classification="distribution-candidate"
if [ "$get_task_allow" = "true" ]; then
  classification="local-qa-ready"
fi

app_profile_summary="$(profile_summary "$app_path" "main app" "$app_bundle_id")"
share_profile_summary=""
if [ -d "$share_path" ]; then
  share_profile_summary="$(profile_summary "$share_path" "share extension" "$share_bundle_id")"
fi

cat <<EOF
Autonomo AV macOS signed build
  app: $app_path
  environment: $env_name
  app bundle: $app_bundle_id
  share bundle: $share_bundle_id
  team: $team_id
  app group: $app_group_id
  keychain service: $expected_keychain_service
  keychain access group: $expected_keychain_access_group
  get-task-allow: ${get_task_allow:-unknown}
  classification: $classification
$app_profile_summary
$share_profile_summary
EOF

if [ "$failures" -gt 0 ]; then
  exit 1
fi

echo "Signed build check passed."
