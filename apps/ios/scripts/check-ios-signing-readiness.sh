#!/usr/bin/env bash
set -euo pipefail

ios_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
env_name=""
mode=""
team_id="935PM55U6R"

usage() {
  cat <<'USAGE'
Usage:
  scripts/check-ios-signing-readiness.sh --env dev|prod [--mode device-dev|testflight]

Checks local Apple signing readiness for Autonomo AV without archiving,
exporting, uploading, or contacting App Store Connect.

Modes:
  device-dev   Requires Apple Development identity and local profiles.
  testflight   Requires Apple Distribution identity and local profiles.

Default mode is device-dev for dev and testflight for prod.
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --env)
      env_name="${2:-}"
      shift 2
      ;;
    --mode)
      mode="${2:-}"
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

if [ -z "$mode" ]; then
  if [ "$env_name" = "prod" ]; then
    mode="testflight"
  else
    mode="device-dev"
  fi
fi

if [ "$mode" != "device-dev" ] && [ "$mode" != "testflight" ]; then
  echo "--mode must be device-dev or testflight." >&2
  exit 2
fi

if [ "$env_name" = "prod" ]; then
  app_bundle_id="com.avalsys.autonomoav"
  app_group_id="group.com.avalsys.autonomoav"
else
  app_bundle_id="com.avalsys.autonomoav.dev"
  app_group_id="group.com.avalsys.autonomoav.dev"
fi
share_bundle_id="$app_bundle_id.share"
profiles_dir="$HOME/Library/MobileDevice/Provisioning Profiles"

failures=0
fail() {
  printf 'FAIL %s\n' "$1" >&2
  failures=$((failures + 1))
}

identity_label="Apple Development"
if [ "$mode" = "testflight" ]; then
  identity_label="Apple Distribution"
fi

if ! security find-identity -v -p codesigning | grep -F "$identity_label" | grep -Fq "($team_id)"; then
  fail "missing $identity_label signing identity for team $team_id"
fi

profile_matches_bundle() {
  local profile="$1"
  local bundle_id="$2"
  local app_group="$3"
  local plist
  plist="$(mktemp)"
  if ! security cms -D -i "$profile" > "$plist" 2>/dev/null; then
    rm -f "$plist"
    return 1
  fi

  local application_identifier
  local team_identifier
  local groups
  application_identifier="$(/usr/libexec/PlistBuddy -c "Print :Entitlements:application-identifier" "$plist" 2>/dev/null || true)"
  team_identifier="$(/usr/libexec/PlistBuddy -c "Print :TeamIdentifier:0" "$plist" 2>/dev/null || true)"
  groups="$(/usr/libexec/PlistBuddy -c "Print :Entitlements:com.apple.security.application-groups" "$plist" 2>/dev/null || true)"
  rm -f "$plist"

  [ "$team_identifier" = "$team_id" ] &&
    [ "$application_identifier" = "$team_id.$bundle_id" ] &&
    printf '%s' "$groups" | grep -Fq "$app_group"
}

find_profile_for_bundle() {
  local bundle_id="$1"
  local app_group="$2"
  local profile

  if [ ! -d "$profiles_dir" ]; then
    return 1
  fi

  while IFS= read -r profile; do
    if profile_matches_bundle "$profile" "$bundle_id" "$app_group"; then
      printf '%s\n' "$profile"
      return 0
    fi
  done < <(find "$profiles_dir" -maxdepth 1 -type f \( -name '*.mobileprovision' -o -name '*.provisionprofile' \) -print 2>/dev/null)

  return 1
}

app_profile="$(find_profile_for_bundle "$app_bundle_id" "$app_group_id" || true)"
share_profile="$(find_profile_for_bundle "$share_bundle_id" "$app_group_id" || true)"

if [ -z "$app_profile" ]; then
  fail "missing local provisioning profile for $app_bundle_id with app group $app_group_id"
fi
if [ -z "$share_profile" ]; then
  fail "missing local provisioning profile for $share_bundle_id with app group $app_group_id"
fi

cat <<EOF
Autonomo AV iOS signing readiness
  environment: $env_name
  mode: $mode
  team: $team_id
  identity: $identity_label
  app bundle: $app_bundle_id
  share bundle: $share_bundle_id
  app group: $app_group_id
  app profile: ${app_profile:-missing}
  share profile: ${share_profile:-missing}
EOF

if [ "$failures" -gt 0 ]; then
  exit 1
fi

echo "Signing readiness check passed."
