#!/usr/bin/env bash
set -euo pipefail

ios_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
product_root="$(cd "$ios_root/../.." && pwd)"
archive_path=""
export_path=""
upload=0
internal_only=0
allow_provisioning_updates=0
team_id="935PM55U6R"
auth_key_path=""
auth_key_id=""
auth_key_issuer_id=""

usage() {
  cat <<'USAGE'
Usage:
  scripts/ios-export-testflight-ipa.sh --archive <AutonomoAV.xcarchive>
    [--export-path <path>] [--allow-provisioning-updates]
    [--upload] [--internal-only]
    [--authentication-key-path <path> --authentication-key-id <id>
      --authentication-key-issuer-id <issuer-id>]

Exports a verified Autonomo AV release archive for App Store Connect/TestFlight.
By default this creates a local .ipa and does not upload anything. Pass
--upload explicitly to ask xcodebuild to upload to App Store Connect.

Use --allow-provisioning-updates only on a Mac signed into the correct Apple
Developer team, or together with App Store Connect API key arguments, when
Xcode should create or download missing App Store/TestFlight profiles.
USAGE
}

run_step() {
  echo
  echo "==> $*"
}

fail() {
  echo "FAIL $*" >&2
  exit 1
}

plist_print() {
  /usr/libexec/PlistBuddy -c "Print :$2" "$1" 2>/dev/null || true
}

plist_add_bool() {
  local path="$1"
  local key="$2"
  local value="$3"
  /usr/libexec/PlistBuddy -c "Add :$key bool $value" "$path"
}

plist_add_string() {
  local path="$1"
  local key="$2"
  local value="$3"
  /usr/libexec/PlistBuddy -c "Add :$key string $value" "$path"
}

codesign_team_for() {
  codesign -dv "$1" 2>&1 | awk -F= '/TeamIdentifier=/ {print $2; exit}'
}

entitlements_for() {
  codesign -d --entitlements :- "$1" 2>/dev/null
}

profile_plist_for() {
  local profile="$1"
  local output="$2"
  security cms -D -i "$profile" > "$output" 2>/dev/null
}

first_app_group_for() {
  /usr/libexec/PlistBuddy -c "Print :com.apple.security.application-groups:0" "$1" 2>/dev/null || true
}

get_task_allow_for() {
  /usr/libexec/PlistBuddy -c "Print :get-task-allow" "$1" 2>/dev/null || true
}

profile_has_provisioned_devices() {
  local plist="$1"
  /usr/libexec/PlistBuddy -c "Print :ProvisionedDevices" "$plist" >/dev/null 2>&1
}

validate_distribution_profile() {
  local profile="$1"
  local bundle_id="$2"
  local app_group="$3"
  local tmp_plist
  local application_identifier
  local profile_team_id
  local profile_group
  local get_task_allow
  local provisions_all_devices

  tmp_plist="$(mktemp)"
  profile_plist_for "$profile" "$tmp_plist"
  application_identifier="$(plist_print "$tmp_plist" "Entitlements:application-identifier")"
  profile_team_id="$(plist_print "$tmp_plist" "TeamIdentifier:0")"
  profile_group="$(plist_print "$tmp_plist" "Entitlements:com.apple.security.application-groups:0")"
  get_task_allow="$(plist_print "$tmp_plist" "Entitlements:get-task-allow")"
  provisions_all_devices="$(plist_print "$tmp_plist" "ProvisionsAllDevices")"

  [ "$profile_team_id" = "$team_id" ] || fail "$bundle_id profile team must be $team_id, got ${profile_team_id:-<missing>}"
  [ "$application_identifier" = "$team_id.$bundle_id" ] || fail "$bundle_id profile application identifier mismatch"
  [ "$profile_group" = "$app_group" ] || fail "$bundle_id profile app group must be $app_group"
  [ "$get_task_allow" = "false" ] || fail "$bundle_id profile must disable get-task-allow"
  if profile_has_provisioned_devices "$tmp_plist"; then
    fail "$bundle_id profile contains provisioned devices; expected App Store/TestFlight profile"
  fi
  [ "$provisions_all_devices" != "true" ] || fail "$bundle_id profile is enterprise-style, not App Store/TestFlight"

  rm -f "$tmp_plist"
}

verify_exported_ipa() {
  local ipa_path="$1"
  local tmp_dir
  local app_path
  local share_path
  local app_info
  local share_info
  local app_entitlements
  local share_entitlements
  local app_bundle_id
  local share_bundle_id
  local app_group
  local share_app_group

  tmp_dir="$(mktemp -d)"
  unzip -q "$ipa_path" -d "$tmp_dir"

  app_paths=()
  while IFS= read -r app_candidate; do
    app_paths+=("$app_candidate")
  done < <(find "$tmp_dir/Payload" -maxdepth 1 -type d -name "*.app" -print | sort)
  [ "${#app_paths[@]}" -eq 1 ] || fail "expected exactly one app in IPA payload, found ${#app_paths[@]}"
  app_path="${app_paths[0]}"
  app_info="$app_path/Info.plist"
  [ -f "$app_info" ] || fail "exported app Info.plist is missing"

  share_paths=()
  while IFS= read -r share_candidate; do
    share_paths+=("$share_candidate")
  done < <(find "$app_path/PlugIns" -maxdepth 1 -type d -name "*.appex" -print | sort)
  [ "${#share_paths[@]}" -eq 1 ] || fail "expected exactly one Share Extension in exported IPA, found ${#share_paths[@]}"
  share_path="${share_paths[0]}"
  share_info="$share_path/Info.plist"
  [ -f "$share_info" ] || fail "exported Share Extension Info.plist is missing"

  app_bundle_id="$(plist_print "$app_info" "CFBundleIdentifier")"
  share_bundle_id="$(plist_print "$share_info" "CFBundleIdentifier")"
  app_group="$(plist_print "$app_info" "AUTONOMOAV_APP_GROUP_IDENTIFIER")"
  share_app_group="$(plist_print "$share_info" "AUTONOMOAV_APP_GROUP_IDENTIFIER")"

  [ "$app_bundle_id" = "com.avalsys.autonomoav" ] || fail "exported app bundle id must be com.avalsys.autonomoav, got ${app_bundle_id:-<missing>}"
  [ "$share_bundle_id" = "com.avalsys.autonomoav.share" ] || fail "exported Share Extension bundle id must be com.avalsys.autonomoav.share, got ${share_bundle_id:-<missing>}"
  [ "$app_group" = "group.com.avalsys.autonomoav" ] || fail "exported app Info.plist app group mismatch"
  [ "$share_app_group" = "group.com.avalsys.autonomoav" ] || fail "exported Share Extension Info.plist app group mismatch"
  [ "$(codesign_team_for "$app_path")" = "$team_id" ] || fail "exported app codesign team mismatch"
  [ "$(codesign_team_for "$share_path")" = "$team_id" ] || fail "exported Share Extension codesign team mismatch"

  app_entitlements="$(mktemp)"
  share_entitlements="$(mktemp)"
  entitlements_for "$app_path" > "$app_entitlements"
  entitlements_for "$share_path" > "$share_entitlements"
  [ "$(first_app_group_for "$app_entitlements")" = "group.com.avalsys.autonomoav" ] || fail "exported app signed entitlements missing app group"
  [ "$(first_app_group_for "$share_entitlements")" = "group.com.avalsys.autonomoav" ] || fail "exported Share Extension signed entitlements missing app group"
  [ "$(get_task_allow_for "$app_entitlements")" = "false" ] || fail "exported app must disable get-task-allow"
  [ "$(get_task_allow_for "$share_entitlements")" = "false" ] || fail "exported Share Extension must disable get-task-allow"

  [ -f "$app_path/embedded.mobileprovision" ] || fail "exported app embedded.mobileprovision is missing"
  [ -f "$share_path/embedded.mobileprovision" ] || fail "exported Share Extension embedded.mobileprovision is missing"
  validate_distribution_profile "$app_path/embedded.mobileprovision" "$app_bundle_id" "group.com.avalsys.autonomoav"
  validate_distribution_profile "$share_path/embedded.mobileprovision" "$share_bundle_id" "group.com.avalsys.autonomoav"

  rm -rf "$tmp_dir" "$app_entitlements" "$share_entitlements"
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --archive)
      archive_path="${2:-}"
      shift 2
      ;;
    --export-path)
      export_path="${2:-}"
      shift 2
      ;;
    --allow-provisioning-updates)
      allow_provisioning_updates=1
      shift
      ;;
    --upload)
      upload=1
      shift
      ;;
    --internal-only)
      internal_only=1
      shift
      ;;
    --authentication-key-path)
      auth_key_path="${2:-}"
      shift 2
      ;;
    --authentication-key-id)
      auth_key_id="${2:-}"
      shift 2
      ;;
    --authentication-key-issuer-id)
      auth_key_issuer_id="${2:-}"
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

[ -n "$archive_path" ] || fail "--archive is required."
[ -d "$archive_path" ] || fail "archive not found: $archive_path"
case "$archive_path" in
  *.xcarchive) ;;
  *) fail "--archive must point to a .xcarchive bundle: $archive_path" ;;
esac

archive_path="$(cd "$(dirname "$archive_path")" && pwd)/$(basename "$archive_path")"
app_info="$archive_path/Products/Applications/AutonomoAV.app/Info.plist"
[ -f "$app_info" ] || fail "archive app Info.plist is missing: $app_info"
build_number="$(plist_print "$app_info" "CFBundleVersion")"
version_number="$(plist_print "$app_info" "CFBundleShortVersionString")"

if [ -z "$export_path" ]; then
  timestamp="$(date '+%Y-%m-%d-%H%M%S')"
  export_path="$product_root/.derived-data/testflight-exports/AutonomoAV-${version_number}-${build_number}-${timestamp}"
fi
mkdir -p "$export_path"
export_path="$(cd "$export_path" && pwd)"

if [ -n "$auth_key_path" ] || [ -n "$auth_key_id" ] || [ -n "$auth_key_issuer_id" ]; then
  [ -n "$auth_key_path" ] || fail "--authentication-key-path is required when using App Store Connect API key auth"
  [ -n "$auth_key_id" ] || fail "--authentication-key-id is required when using App Store Connect API key auth"
  [ -n "$auth_key_issuer_id" ] || fail "--authentication-key-issuer-id is required when using App Store Connect API key auth"
fi

destination="export"
if [ "$upload" -eq 1 ]; then
  destination="upload"
fi

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
export_options="$tmp_dir/ExportOptions.plist"
/usr/bin/plutil -create xml1 "$export_options"
plist_add_string "$export_options" "method" "app-store-connect"
plist_add_string "$export_options" "destination" "$destination"
plist_add_string "$export_options" "signingStyle" "automatic"
plist_add_string "$export_options" "teamID" "$team_id"
plist_add_bool "$export_options" "stripSwiftSymbols" "true"
plist_add_bool "$export_options" "uploadSymbols" "true"
plist_add_bool "$export_options" "manageAppVersionAndBuildNumber" "false"
if [ "$internal_only" -eq 1 ]; then
  plist_add_bool "$export_options" "testFlightInternalTestingOnly" "true"
fi

run_step "Verify source archive"
"$ios_root/scripts/check-ios-release-archive.sh" \
  --archive "$archive_path" \
  --expected-build "$build_number" \
  --expected-version "$version_number"

if [ "$allow_provisioning_updates" -eq 0 ] && [ "$upload" -eq 0 ]; then
  run_step "Check local App Store/TestFlight signing readiness"
  "$ios_root/scripts/check-ios-signing-readiness.sh" --env prod --mode testflight
fi

run_step "Export archive for App Store Connect"
export_args=(xcodebuild -exportArchive \
  -archivePath "$archive_path" \
  -exportPath "$export_path" \
  -exportOptionsPlist "$export_options")
if [ "$allow_provisioning_updates" -eq 1 ]; then
  export_args+=(-allowProvisioningUpdates)
fi
if [ -n "$auth_key_path" ]; then
  export_args+=(-authenticationKeyPath "$auth_key_path" -authenticationKeyID "$auth_key_id" -authenticationKeyIssuerID "$auth_key_issuer_id")
fi
"${export_args[@]}"

if [ "$upload" -eq 0 ]; then
  ipa_paths=()
  while IFS= read -r ipa_candidate; do
    ipa_paths+=("$ipa_candidate")
  done < <(find "$export_path" -maxdepth 1 -type f -name "*.ipa" -print | sort)
  [ "${#ipa_paths[@]}" -eq 1 ] || fail "expected exactly one exported .ipa in $export_path, found ${#ipa_paths[@]}"

  run_step "Verify exported IPA"
  verify_exported_ipa "${ipa_paths[0]}"

  cat <<REPORT

Autonomo AV TestFlight IPA export passed.
  ipa: ${ipa_paths[0]}
  archive: $archive_path
  destination: export
REPORT
else
  cat <<REPORT

Autonomo AV upload command completed.
  archive: $archive_path
  destination: upload
REPORT
fi
