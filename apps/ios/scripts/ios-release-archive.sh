#!/usr/bin/env bash
set -euo pipefail

ios_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
product_root="$(cd "$ios_root/../.." && pwd)"
archive_path=""
build_number=""
version_number=""
skip_preflight=0
allow_provisioning_updates=0
use_existing_archive=0

usage() {
  cat <<'USAGE'
Usage:
  scripts/ios-release-archive.sh [--build <build>] [--version <version>]
    [--archive <path>] [--skip-preflight] [--allow-provisioning-updates]

Creates and verifies an Autonomo AV iOS release archive for TestFlight
readiness. Under automatic signing, Xcode creates the archive with Apple
Development signing; App Store/TestFlight distribution signing happens during
export/upload. This script does not export, upload, or contact App Store
Connect.

Use --allow-provisioning-updates only on a Mac signed into the correct Apple
Developer team when you intentionally want Xcode to repair local profiles.
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --archive)
      archive_path="${2:-}"
      shift 2
      ;;
    --build)
      build_number="${2:-}"
      shift 2
      ;;
    --version)
      version_number="${2:-}"
      shift 2
      ;;
    --skip-preflight)
      skip_preflight=1
      shift
      ;;
    --allow-provisioning-updates)
      allow_provisioning_updates=1
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

run_step() {
  echo
  echo "==> $*"
}

plist_set() {
  local key="$1"
  local value="$2"
  /usr/libexec/PlistBuddy -c "Set :$key $value" "$ios_root/AutonomoAV/App/Info.plist"
  /usr/libexec/PlistBuddy -c "Set :$key $value" "$ios_root/AutonomoAVShareExtension/Info.plist"
}

plist_get() {
  /usr/libexec/PlistBuddy -c "Print :$1" "$ios_root/AutonomoAV/App/Info.plist"
}

if [ -n "$archive_path" ] && [ -d "$archive_path" ]; then
  use_existing_archive=1
  archive_path="$(cd "$(dirname "$archive_path")" && pwd)/$(basename "$archive_path")"
fi

if [ "$use_existing_archive" -eq 0 ]; then
  if [ -n "$build_number" ]; then
    run_step "Set iOS build number $build_number"
    plist_set "CFBundleVersion" "$build_number"
  fi

  if [ -n "$version_number" ]; then
    run_step "Set iOS marketing version $version_number"
    plist_set "CFBundleShortVersionString" "$version_number"
  fi

  build_number="$(plist_get "CFBundleVersion")"
  version_number="$(plist_get "CFBundleShortVersionString")"
else
  app_info="$archive_path/Products/Applications/AutonomoAV.app/Info.plist"
  [ -f "$app_info" ] || { echo "Existing archive app Info.plist is missing: $app_info" >&2; exit 1; }
  if [ -z "$build_number" ]; then
    build_number="$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$app_info")"
  fi
  if [ -z "$version_number" ]; then
    version_number="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$app_info")"
  fi
fi

if [ -z "$archive_path" ]; then
  timestamp="$(date '+%Y-%m-%d-%H%M%S')"
  archive_path="$product_root/.derived-data/release-archives/AutonomoAV-${version_number}-${build_number}-${timestamp}.xcarchive"
fi

mkdir -p "$(dirname "$archive_path")"

if [ "$use_existing_archive" -eq 0 ]; then
  if command -v xcodegen >/dev/null 2>&1; then
    run_step "Generate Xcode project"
    (cd "$ios_root" && xcodegen generate)
  fi

  if [ "$skip_preflight" -eq 0 ]; then
    run_step "Run production runtime and Share Extension preflight"
    "$ios_root/scripts/check-ios-release-preflight.sh" --env prod --configuration Release --skip-build

    if [ "$allow_provisioning_updates" -eq 0 ]; then
      run_step "Check local production archive signing readiness"
      "$ios_root/scripts/check-ios-signing-readiness.sh" --env prod --mode device-dev
    fi
  fi

  provisioning_args=()
  if [ "$allow_provisioning_updates" -eq 1 ]; then
    provisioning_args=(-allowProvisioningUpdates)
  fi

  run_step "Archive signed iOS release"
  xcodebuild archive \
    -project "$ios_root/AutonomoAV.xcodeproj" \
    -scheme AutonomoAV \
    -configuration Release \
    -destination "generic/platform=iOS" \
    -archivePath "$archive_path" \
    "${provisioning_args[@]}" \
    DEVELOPMENT_TEAM=935PM55U6R \
    "CODE_SIGN_IDENTITY=Apple Development" \
    CODE_SIGN_STYLE=Automatic

  if [ "$allow_provisioning_updates" -eq 1 ]; then
    run_step "Check local production archive signing readiness after provisioning"
    "$ios_root/scripts/check-ios-signing-readiness.sh" --env prod --mode device-dev
  fi
else
  run_step "Use existing iOS archive"
  echo "$archive_path"
fi

run_step "Verify final iOS release archive"
"$ios_root/scripts/check-ios-release-archive.sh" \
  --archive "$archive_path" \
  --expected-build "$build_number" \
  --expected-version "$version_number"

cat <<REPORT

Verified Autonomo AV archive is ready for manual TestFlight export/upload.
Distribution signing is expected in the export/upload step.
  archive: $archive_path

This script intentionally did not export or upload the archive.
REPORT
