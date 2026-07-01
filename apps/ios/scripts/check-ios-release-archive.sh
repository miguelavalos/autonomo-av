#!/usr/bin/env bash
set -euo pipefail

archive_path=""
expected_build=""
expected_version=""
expected_bundle_id="${AUTONOMOAV_IOS_BUNDLE_ID:-com.avalsys.autonomoav}"
expected_team_id="${AUTONOMOAV_APPLE_TEAM_ID:-935PM55U6R}"
expected_app_group="${AUTONOMOAV_APP_GROUP_ID:-group.com.avalsys.autonomoav}"
expected_share_bundle_id="${AUTONOMOAV_SHARE_BUNDLE_ID:-$expected_bundle_id.share}"

usage() {
  cat <<'USAGE'
Usage:
  scripts/check-ios-release-archive.sh --archive <AutonomoAV.xcarchive>
    [--expected-build <build>] [--expected-version <version>]

Validates the final Autonomo AV iOS release archive before any upload:
- app version and build;
- app and Share Extension bundle identifiers;
- signing team metadata;
- app group entitlements on both signed products;
- arm64 archive architecture;
- app and Share Extension dSYM UUIDs.

This script does not export, upload, or contact App Store Connect.
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --archive)
      archive_path="${2:-}"
      shift 2
      ;;
    --expected-build)
      expected_build="${2:-}"
      shift 2
      ;;
    --expected-version)
      expected_version="${2:-}"
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

fail() {
  echo "FAIL $*" >&2
  exit 1
}

plist_print() {
  /usr/libexec/PlistBuddy -c "Print :$2" "$1" 2>/dev/null || true
}

uuid_for() {
  /usr/bin/dwarfdump --uuid "$1" 2>/dev/null | awk '/UUID:/ {print $2; exit}'
}

codesign_team_for() {
  codesign -dv "$1" 2>&1 | awk -F= '/TeamIdentifier=/ {print $2; exit}'
}

entitlements_for() {
  codesign -d --entitlements :- "$1" 2>/dev/null
}

first_app_group_for() {
  /usr/libexec/PlistBuddy -c "Print :com.apple.security.application-groups:0" "$1" 2>/dev/null || true
}

find_dsym_matching_uuid() {
  local wanted_uuid="$1"
  local dsym

  while IFS= read -r dsym; do
    if [ "$(uuid_for "$dsym")" = "$wanted_uuid" ]; then
      printf '%s\n' "$dsym"
      return 0
    fi
  done < <(find "$archive_path/dSYMs" -maxdepth 1 -type d -name '*.dSYM' -print 2>/dev/null)

  return 1
}

[ -n "$archive_path" ] || fail "--archive is required."
case "$archive_path" in
  *.xcarchive) ;;
  *) fail "--archive must point to a .xcarchive bundle: $archive_path" ;;
esac
[ -d "$archive_path" ] || fail "archive not found: $archive_path"

archive_path="$(cd "$(dirname "$archive_path")" && pwd)/$(basename "$archive_path")"
app_path="$archive_path/Products/Applications/AutonomoAV.app"
app_info="$app_path/Info.plist"
[ -d "$app_path" ] || fail "archive app is missing: $app_path"
[ -f "$app_info" ] || fail "archive app Info.plist is missing: $app_info"

if [ -d "$archive_path/Products/Users" ]; then
  fail "archive contains installed intermediate products under Products/Users; do not override SKIP_INSTALL globally"
fi

plugins_dir="$app_path/PlugIns"
[ -d "$plugins_dir" ] || fail "archive app PlugIns directory is missing"
appex_paths=()
while IFS= read -r appex_path; do
  appex_paths+=("$appex_path")
done < <(find "$plugins_dir" -maxdepth 1 -type d -name '*.appex' -print | sort)
[ "${#appex_paths[@]}" -eq 1 ] || fail "expected exactly one Share Extension .appex, found ${#appex_paths[@]}"
share_path="${appex_paths[0]}"
share_info="$share_path/Info.plist"
[ -f "$share_info" ] || fail "Share Extension Info.plist is missing: $share_info"

version="$(plist_print "$app_info" "CFBundleShortVersionString")"
build="$(plist_print "$app_info" "CFBundleVersion")"
bundle_id="$(plist_print "$app_info" "CFBundleIdentifier")"
app_group="$(plist_print "$app_info" "AUTONOMOAV_APP_GROUP_IDENTIFIER")"
share_bundle_id="$(plist_print "$share_info" "CFBundleIdentifier")"
share_display_name="$(plist_print "$share_info" "CFBundleDisplayName")"
share_app_group="$(plist_print "$share_info" "AUTONOMOAV_APP_GROUP_IDENTIFIER")"
archive_team="$(plist_print "$archive_path/Info.plist" "ApplicationProperties:Team")"
architectures="$(plist_print "$archive_path/Info.plist" "ApplicationProperties:Architectures")"
app_binary="$app_path/AutonomoAV"
share_binary="$share_path/$(plist_print "$share_info" "CFBundleExecutable")"

[ "$bundle_id" = "$expected_bundle_id" ] || fail "bundle id must be $expected_bundle_id, got ${bundle_id:-<missing>}"
[ "$share_bundle_id" = "$expected_share_bundle_id" ] || fail "Share Extension bundle id must be $expected_share_bundle_id, got ${share_bundle_id:-<missing>}"
[ "$app_group" = "$expected_app_group" ] || fail "app Info.plist app group must be $expected_app_group, got ${app_group:-<missing>}"
[ "$share_app_group" = "$expected_app_group" ] || fail "Share Extension Info.plist app group must be $expected_app_group, got ${share_app_group:-<missing>}"
[ "$share_display_name" = "Enviar a Autonomo AV Inbox" ] || fail "Share Extension display name changed: ${share_display_name:-<missing>}"
[ -f "$app_binary" ] || fail "app binary is missing: $app_binary"
[ -f "$share_binary" ] || fail "Share Extension binary is missing: $share_binary"
[ -n "$archive_team" ] || fail "archive metadata is missing ApplicationProperties:Team; Xcode will not export this archive"
[ -n "$architectures" ] || fail "archive metadata is missing ApplicationProperties:Architectures; Xcode will not export this archive"

if [ -n "$expected_build" ]; then
  [ "$build" = "$expected_build" ] || fail "build must be $expected_build, got ${build:-<missing>}"
fi
if [ -n "$expected_version" ]; then
  [ "$version" = "$expected_version" ] || fail "version must be $expected_version, got ${version:-<missing>}"
fi

app_codesign_team="$(codesign_team_for "$app_path")"
share_codesign_team="$(codesign_team_for "$share_path")"
[ "$app_codesign_team" = "$expected_team_id" ] || fail "app codesign team must be $expected_team_id, got ${app_codesign_team:-<missing>}"
[ "$share_codesign_team" = "$expected_team_id" ] || fail "Share Extension codesign team must be $expected_team_id, got ${share_codesign_team:-<missing>}"
[ "$archive_team" = "$expected_team_id" ] || fail "archive team must be $expected_team_id, got $archive_team"

echo "$architectures" | grep -q "arm64" || fail "archive architectures must include arm64"

app_entitlements="$(mktemp)"
share_entitlements="$(mktemp)"
trap 'rm -f "$app_entitlements" "$share_entitlements"' EXIT
entitlements_for "$app_path" > "$app_entitlements"
entitlements_for "$share_path" > "$share_entitlements"
[ "$(first_app_group_for "$app_entitlements")" = "$expected_app_group" ] || fail "app signed entitlements must include $expected_app_group"
[ "$(first_app_group_for "$share_entitlements")" = "$expected_app_group" ] || fail "Share Extension signed entitlements must include $expected_app_group"

app_uuid="$(uuid_for "$app_binary")"
share_uuid="$(uuid_for "$share_binary")"
[ -n "$app_uuid" ] || fail "could not read app binary UUID"
[ -n "$share_uuid" ] || fail "could not read Share Extension binary UUID"
app_dsym="$(find_dsym_matching_uuid "$app_uuid" || true)"
share_dsym="$(find_dsym_matching_uuid "$share_uuid" || true)"
[ -n "$app_dsym" ] || fail "matching app dSYM is missing for UUID $app_uuid"
[ -n "$share_dsym" ] || fail "matching Share Extension dSYM is missing for UUID $share_uuid"

cat <<REPORT
Autonomo AV iOS release archive passed.
  archive: $archive_path
  version: $version
  build: $build
  bundle id: $bundle_id
  share bundle id: $share_bundle_id
  app group: $expected_app_group
  team id: $app_codesign_team
  app UUID: $app_uuid
  share UUID: $share_uuid
REPORT
