#!/usr/bin/env bash
set -euo pipefail

macos_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
env_name=""
configuration="Release"
skip_build=0
derived_data_path="$macos_root/.DerivedData-autonomoav-macos-preflight"

usage() {
  cat <<'USAGE'
Usage:
  scripts/check-macos-release-preflight.sh --env dev|prod [--configuration Debug|Release]
    [--skip-build] [--derived-data <path>]

Runs the Autonomo AV macOS release guardrail checks without printing secrets.
This script does not archive, export, upload, or contact App Store Connect.
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
    --skip-build)
      skip_build=1
      shift
      ;;
    --derived-data)
      derived_data_path="${2:-}"
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

failures=0
fail() {
  printf 'FAIL %s\n' "$1" >&2
  failures=$((failures + 1))
}

require_file() {
  local path="$1"
  [ -f "$macos_root/$path" ] || fail "missing $path"
}

require_contains() {
  local path="$1"
  local pattern="$2"
  local message="$3"
  if ! grep -Fq "$pattern" "$macos_root/$path"; then
    fail "$message"
  fi
}

require_absent() {
  local path="$1"
  local pattern="$2"
  local message="$3"
  if grep -Fq "$pattern" "$macos_root/$path"; then
    fail "$message"
  fi
}

if [ "$env_name" = "prod" ] && [ ! -f "$macos_root/Config/Local.xcconfig" ]; then
  fail "prod preflight requires ignored Config/Local.xcconfig generated from private config"
fi

"$macos_root/scripts/check-macos-runtime-config.sh" --env "$env_name" --configuration "$configuration"
node "$macos_root/scripts/check-macos-platform-security.mjs"

require_file "Supporting/AutonomoAVMac.entitlements"
require_file "ShareExtension/AutonomoAVMacShareExtension.entitlements"
require_file "Supporting/Info.plist"
require_file "ShareExtension/Info.plist"
require_file "project.yml"

plutil -lint "$macos_root/Supporting/Info.plist" >/dev/null
plutil -lint "$macos_root/ShareExtension/Info.plist" >/dev/null
plutil -lint "$macos_root/Supporting/AutonomoAVMac.entitlements" >/dev/null
plutil -lint "$macos_root/ShareExtension/AutonomoAVMacShareExtension.entitlements" >/dev/null

require_contains \
  "Supporting/AutonomoAVMac.entitlements" \
  '$(AUTONOMOAV_APP_GROUP_IDENTIFIER)' \
  "main app entitlement must use AUTONOMOAV_APP_GROUP_IDENTIFIER"

require_contains \
  "ShareExtension/AutonomoAVMacShareExtension.entitlements" \
  '$(AUTONOMOAV_APP_GROUP_IDENTIFIER)' \
  "share extension entitlement must use AUTONOMOAV_APP_GROUP_IDENTIFIER"

require_contains \
  "Supporting/AutonomoAVMac.entitlements" \
  '$(ACCOUNTAV_KEYCHAIN_ACCESS_GROUP)' \
  "main app entitlement must use ACCOUNTAV_KEYCHAIN_ACCESS_GROUP"

require_absent \
  "ShareExtension/AutonomoAVMacShareExtension.entitlements" \
  '$(ACCOUNTAV_KEYCHAIN_ACCESS_GROUP)' \
  "share extension must not have Account AV keychain entitlement"

require_contains \
  "Supporting/Info.plist" \
  "AUTONOMOAV_APP_GROUP_IDENTIFIER" \
  "main app Info.plist must expose AUTONOMOAV_APP_GROUP_IDENTIFIER"

require_contains \
  "ShareExtension/Info.plist" \
  "AUTONOMOAV_APP_GROUP_IDENTIFIER" \
  "share extension Info.plist must expose AUTONOMOAV_APP_GROUP_IDENTIFIER"

require_contains \
  "ShareExtension/Info.plist" \
  "<string>Autonomo AV Inbox</string>" \
  "share extension display name must remain Autonomo AV Inbox"

require_contains \
  "ShareExtension/Info.plist" \
  "NSExtensionActivationSupportsFileWithMaxCount" \
  "share extension must support file activation"

require_contains \
  "ShareExtension/Info.plist" \
  "NSExtensionActivationSupportsImageWithMaxCount" \
  "share extension must support image activation"

require_absent \
  "ShareExtension/Info.plist" \
  "NSExtensionActivationSupportsText" \
  "share extension advertises text support but code only imports PDF/image"

require_absent \
  "ShareExtension/Info.plist" \
  "NSExtensionActivationSupportsWebURLWithMaxCount" \
  "share extension advertises URL support but code only imports PDF/image"

require_contains \
  "project.yml" \
  "CODE_SIGN_ENTITLEMENTS: Supporting/AutonomoAVMac.entitlements" \
  "main app target must use checked-in entitlements"

require_contains \
  "project.yml" \
  "CODE_SIGN_ENTITLEMENTS: ShareExtension/AutonomoAVMacShareExtension.entitlements" \
  "share extension target must use checked-in entitlements"

if [ "$failures" -gt 0 ]; then
  exit 1
fi

if [ "$skip_build" -eq 0 ]; then
  xcodebuild \
    -project "$macos_root/AutonomoAVMac.xcodeproj" \
    -scheme AutonomoAVMac \
    -configuration "$configuration" \
    -destination 'platform=macOS' \
    -derivedDataPath "$derived_data_path" \
    build \
    CODE_SIGNING_ALLOWED=NO
fi

cat <<EOF
Autonomo AV macOS release preflight passed.
  environment: $env_name
  configuration: $configuration
  build: $([ "$skip_build" -eq 1 ] && echo skipped || echo passed)
  derived data: $([ "$skip_build" -eq 1 ] && echo none || echo "$derived_data_path")
EOF
