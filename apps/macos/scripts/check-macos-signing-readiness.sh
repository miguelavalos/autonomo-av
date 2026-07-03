#!/usr/bin/env bash
set -euo pipefail

env_name=""
mode=""
team_id="935PM55U6R"

usage() {
  cat <<'USAGE'
Usage:
  scripts/check-macos-signing-readiness.sh --env dev|prod [--mode device-dev|testflight]

Checks local Apple signing readiness for Autonomo AV macOS without archiving,
exporting, uploading, or contacting App Store Connect.

Modes:
  device-dev   Requires Apple Development identity and local profiles.
  testflight   Requires Apple Distribution identity and App Store/TestFlight profiles.

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
  app_bundle_id="com.avalsys.autonomoav.mac"
  app_group_id="group.com.avalsys.autonomoav"
else
  app_bundle_id="com.avalsys.autonomoav.mac.dev"
  app_group_id="group.com.avalsys.autonomoav.dev"
fi
share_bundle_id="$app_bundle_id.share"
profiles_dirs=(
  "$HOME/Library/MobileDevice/Provisioning Profiles"
  "$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"
)

failures=0
fail() {
  printf 'FAIL %s\n' "$1" >&2
  failures=$((failures + 1))
}

identity_label="Apple Development"
profile_kind_label="development"
if [ "$mode" = "testflight" ]; then
  identity_label="Apple Distribution"
  profile_kind_label="App Store/TestFlight"
fi

identity_matches_team() {
  local identity_line
  local identity_name
  local subject

  while IFS= read -r identity_line; do
    case "$identity_line" in
      *"$identity_label"*)
        identity_name="${identity_line#*\"}"
        identity_name="${identity_name%\"*}"
        subject="$(security find-certificate -c "$identity_name" -p 2>/dev/null | openssl x509 -noout -subject 2>/dev/null || true)"
        if printf '%s' "$subject" | grep -Eq "OU[ =/]+$team_id"; then
          return 0
        fi
        ;;
    esac
  done < <(security find-identity -v -p codesigning)

  return 1
}

if ! identity_matches_team; then
  fail "missing $identity_label signing identity for team $team_id"
fi

plist_value() {
  /usr/libexec/PlistBuddy -c "Print :$2" "$1" 2>/dev/null || true
}

profile_application_identifier() {
  local plist="$1"
  local value
  value="$(plist_value "$plist" "Entitlements:com.apple.application-identifier")"
  if [ -n "$value" ]; then
    printf '%s\n' "$value"
    return
  fi
  plist_value "$plist" "Entitlements:application-identifier"
}

profile_team_identifier() {
  local plist="$1"
  local value
  value="$(plist_value "$plist" "TeamIdentifier:0")"
  if [ -n "$value" ]; then
    printf '%s\n' "$value"
    return
  fi
  plist_value "$plist" "Entitlements:com.apple.developer.team-identifier"
}

profile_get_task_allow() {
  local plist="$1"
  local value
  value="$(plist_value "$plist" "Entitlements:get-task-allow")"
  if [ -n "$value" ]; then
    printf '%s\n' "$value"
    return
  fi
  plist_value "$plist" "Entitlements:com.apple.security.get-task-allow"
}

profile_groups() {
  plist_value "$1" "Entitlements:com.apple.security.application-groups"
}

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
  local get_task_allow
  local has_provisioned_devices=0
  local provisions_all_devices
  application_identifier="$(profile_application_identifier "$plist")"
  team_identifier="$(profile_team_identifier "$plist")"
  groups="$(profile_groups "$plist")"
  get_task_allow="$(profile_get_task_allow "$plist")"
  if /usr/libexec/PlistBuddy -c "Print :ProvisionedDevices" "$plist" >/dev/null 2>&1; then
    has_provisioned_devices=1
  fi
  provisions_all_devices="$(plist_value "$plist" "ProvisionsAllDevices")"
  rm -f "$plist"

  [ "$team_identifier" = "$team_id" ] || return 1
  [ "$application_identifier" = "$team_id.$bundle_id" ] || return 1
  printf '%s' "$groups" | grep -Fq "$app_group" || return 1

  if [ "$mode" = "testflight" ]; then
    [ "$get_task_allow" != "true" ] || return 1
    [ "$has_provisioned_devices" -eq 0 ] || return 1
    [ "$provisions_all_devices" != "true" ] || return 1
  else
    [ "$has_provisioned_devices" -eq 1 ] || return 1
  fi
}

profile_hint_line() {
  local prefix="$1"
  local profile="$2"
  local plist="$3"
  local bundle_id="$4"
  local app_group="$5"
  local application_identifier
  local groups
  local has_app_group="no"
  local has_provisioned_devices="no"

  application_identifier="$(profile_application_identifier "$plist")"
  groups="$(profile_groups "$plist")"
  if printf '%s' "$groups" | grep -Fq "$app_group"; then
    has_app_group="yes"
  fi
  if /usr/libexec/PlistBuddy -c "Print :ProvisionedDevices" "$plist" >/dev/null 2>&1; then
    has_provisioned_devices="yes"
  fi

  printf '%s %s (%s, app-group=%s, devices=%s, path=%s)\n' \
    "$prefix" \
    "$(plist_value "$plist" Name)" \
    "${application_identifier:-missing}" \
    "$has_app_group" \
    "$has_provisioned_devices" \
    "$profile"
}

nearest_profile_for_bundle() {
  local bundle_id="$1"
  local app_group="$2"
  local exact_hint=""
  local wildcard_hint=""
  local team_hint=""
  local profiles_dir
  local profile
  local plist
  local application_identifier
  local team_identifier

  for profiles_dir in "${profiles_dirs[@]}"; do
    if [ ! -d "$profiles_dir" ]; then
      continue
    fi

    while IFS= read -r profile; do
      plist="$(mktemp)"
      if ! security cms -D -i "$profile" > "$plist" 2>/dev/null; then
        rm -f "$plist"
        continue
      fi

      team_identifier="$(profile_team_identifier "$plist")"
      if [ "$team_identifier" = "$team_id" ]; then
        application_identifier="$(profile_application_identifier "$plist")"
        if [ "$application_identifier" = "$team_id.$bundle_id" ] && [ -z "$exact_hint" ]; then
          exact_hint="$(profile_hint_line "exact profile candidate:" "$profile" "$plist" "$bundle_id" "$app_group")"
        elif [ "$application_identifier" = "$team_id.*" ] && [ -z "$wildcard_hint" ]; then
          wildcard_hint="$(profile_hint_line "wildcard profile candidate:" "$profile" "$plist" "$bundle_id" "$app_group")"
        elif [ -z "$team_hint" ]; then
          team_hint="$(profile_hint_line "same-team profile candidate:" "$profile" "$plist" "$bundle_id" "$app_group")"
        fi
      fi

      rm -f "$plist"
    done < <(find "$profiles_dir" -maxdepth 1 -type f \( -name '*.mobileprovision' -o -name '*.provisionprofile' \) -print 2>/dev/null)
  done

  if [ -n "$exact_hint" ]; then
    printf '%s\n' "$exact_hint"
  elif [ -n "$wildcard_hint" ]; then
    printf '%s\n' "$wildcard_hint"
  elif [ -n "$team_hint" ]; then
    printf '%s\n' "$team_hint"
  fi
}

find_profile_for_bundle() {
  local bundle_id="$1"
  local app_group="$2"
  local profiles_dir
  local profile

  for profiles_dir in "${profiles_dirs[@]}"; do
    if [ ! -d "$profiles_dir" ]; then
      continue
    fi

    while IFS= read -r profile; do
      if profile_matches_bundle "$profile" "$bundle_id" "$app_group"; then
        printf '%s\n' "$profile"
        return 0
      fi
    done < <(find "$profiles_dir" -maxdepth 1 -type f \( -name '*.mobileprovision' -o -name '*.provisionprofile' \) -print 2>/dev/null)
  done

  return 1
}

app_profile="$(find_profile_for_bundle "$app_bundle_id" "$app_group_id" || true)"
share_profile="$(find_profile_for_bundle "$share_bundle_id" "$app_group_id" || true)"
app_profile_hint=""
share_profile_hint=""

if [ -z "$app_profile" ]; then
  app_profile_hint="$(nearest_profile_for_bundle "$app_bundle_id" "$app_group_id")"
  fail "missing local $profile_kind_label provisioning profile for $app_bundle_id with app group $app_group_id"
fi
if [ -z "$share_profile" ]; then
  share_profile_hint="$(nearest_profile_for_bundle "$share_bundle_id" "$app_group_id")"
  fail "missing local $profile_kind_label provisioning profile for $share_bundle_id with app group $app_group_id"
fi

cat <<EOF
Autonomo AV macOS signing readiness
  environment: $env_name
  mode: $mode
  team: $team_id
  identity: $identity_label
  app bundle: $app_bundle_id
  share bundle: $share_bundle_id
  app group: $app_group_id
  app profile: ${app_profile:-missing}
  share profile: ${share_profile:-missing}
  app profile hint: ${app_profile_hint:-none}
  share profile hint: ${share_profile_hint:-none}
EOF

if [ "$failures" -gt 0 ]; then
  exit 1
fi

echo "Signing readiness check passed."
