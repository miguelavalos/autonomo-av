#!/usr/bin/env bash
set -euo pipefail

ios_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
env_name=""
configuration="Release"
skip_build=0
derived_data_path="$ios_root/.DerivedData-autonomoav-ios-preflight"
keep_derived_data=0
build_started=0

usage() {
  cat <<'USAGE'
Usage:
  scripts/check-ios-release-preflight.sh --env dev|prod [--configuration Debug|Release]
    [--skip-build] [--derived-data-path <path>] [--keep-derived-data]

Runs the Autonomo AV iOS release guardrail checks without printing secrets.
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
    --derived-data-path)
      derived_data_path="${2:-}"
      shift 2
      ;;
    --keep-derived-data)
      keep_derived_data=1
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

if [ "$configuration" != "Debug" ] && [ "$configuration" != "Release" ]; then
  echo "--configuration must be Debug or Release." >&2
  exit 2
fi

if [ -z "$derived_data_path" ]; then
  echo "--derived-data-path must not be empty." >&2
  exit 2
fi

derived_data_dir="$(cd "$(dirname "$derived_data_path")" && pwd)"
derived_data_path="$derived_data_dir/$(basename "$derived_data_path")"

cleanup() {
  local status=$?
  if [ "$skip_build" -eq 0 ] && [ "$build_started" -eq 1 ] && [ -d "$derived_data_path" ]; then
    if [ "$status" -eq 0 ] && [ "$keep_derived_data" -eq 0 ]; then
      du -sh "$derived_data_path"
      rm -rf "$derived_data_path"
    else
      echo "iOS release preflight preserving derived data at $derived_data_path" >&2
    fi
  fi
}
trap cleanup EXIT

failures=0
fail() {
  printf 'FAIL %s\n' "$1" >&2
  failures=$((failures + 1))
}

require_file() {
  local path="$1"
  [ -f "$ios_root/$path" ] || fail "missing $path"
}

require_contains() {
  local path="$1"
  local pattern="$2"
  local message="$3"
  if ! grep -Fq "$pattern" "$ios_root/$path"; then
    fail "$message"
  fi
}

require_absent() {
  local path="$1"
  local pattern="$2"
  local message="$3"
  if grep -Fq "$pattern" "$ios_root/$path"; then
    fail "$message"
  fi
}

if [ "$env_name" = "prod" ] && [ ! -f "$ios_root/Config/Local.xcconfig" ]; then
  fail "prod preflight requires ignored Config/Local.xcconfig generated from private config"
fi

"$ios_root/scripts/check-ios-runtime-config.sh" --env "$env_name" --configuration "$configuration"

require_file "AutonomoAV/App/AutonomoAV.entitlements"
require_file "AutonomoAVShareExtension/AutonomoAVShareExtension.entitlements"
require_file "AutonomoAV/App/Info.plist"
require_file "AutonomoAVShareExtension/Info.plist"
require_file "project.yml"

plutil -lint "$ios_root/AutonomoAV/App/Info.plist" >/dev/null
plutil -lint "$ios_root/AutonomoAVShareExtension/Info.plist" >/dev/null
plutil -lint "$ios_root/AutonomoAV/App/AutonomoAV.entitlements" >/dev/null
plutil -lint "$ios_root/AutonomoAVShareExtension/AutonomoAVShareExtension.entitlements" >/dev/null

require_contains \
  "AutonomoAV/App/AutonomoAV.entitlements" \
  '$(AUTONOMOAV_APP_GROUP_IDENTIFIER)' \
  "main app entitlement must use AUTONOMOAV_APP_GROUP_IDENTIFIER"

require_contains \
  "AutonomoAVShareExtension/AutonomoAVShareExtension.entitlements" \
  '$(AUTONOMOAV_APP_GROUP_IDENTIFIER)' \
  "share extension entitlement must use AUTONOMOAV_APP_GROUP_IDENTIFIER"

require_contains \
  "AutonomoAV/App/Info.plist" \
  "AUTONOMOAV_APP_GROUP_IDENTIFIER" \
  "main app Info.plist must expose AUTONOMOAV_APP_GROUP_IDENTIFIER"

require_contains \
  "AutonomoAVShareExtension/Info.plist" \
  "AUTONOMOAV_APP_GROUP_IDENTIFIER" \
  "share extension Info.plist must expose AUTONOMOAV_APP_GROUP_IDENTIFIER"

require_contains \
  "AutonomoAVShareExtension/Info.plist" \
  "<string>Enviar a Autonomo AV Inbox</string>" \
  "share extension display name must remain Enviar a Autonomo AV Inbox"

require_contains \
  "AutonomoAVShareExtension/Info.plist" \
  "NSExtensionActivationSupportsFileWithMaxCount" \
  "share extension must support file activation"

require_contains \
  "AutonomoAVShareExtension/Info.plist" \
  "NSExtensionActivationSupportsImageWithMaxCount" \
  "share extension must support image activation"

require_absent \
  "AutonomoAVShareExtension/Info.plist" \
  "NSExtensionActivationSupportsText" \
  "share extension advertises text support but code only imports PDF/image"

require_absent \
  "AutonomoAVShareExtension/Info.plist" \
  "NSExtensionActivationSupportsWebURLWithMaxCount" \
  "share extension advertises URL support but code only imports PDF/image"

require_contains \
  "project.yml" \
  "CODE_SIGN_ENTITLEMENTS: AutonomoAV/App/AutonomoAV.entitlements" \
  "main app target must use checked-in entitlements"

require_contains \
  "project.yml" \
  "CODE_SIGN_ENTITLEMENTS: AutonomoAVShareExtension/AutonomoAVShareExtension.entitlements" \
  "share extension target must use checked-in entitlements"

if [ "$failures" -gt 0 ]; then
  exit 1
fi

if [ "$skip_build" -eq 0 ]; then
  build_started=1
  xcodebuild \
    -project "$ios_root/AutonomoAV.xcodeproj" \
    -scheme AutonomoAV \
    -configuration "$configuration" \
    -destination 'generic/platform=iOS Simulator' \
    -derivedDataPath "$derived_data_path" \
    build \
    CODE_SIGNING_ALLOWED=NO
fi

cat <<EOF
Autonomo AV iOS release preflight passed.
  environment: $env_name
  configuration: $configuration
  build: $([ "$skip_build" -eq 1 ] && echo skipped || echo passed)
  derived data: $([ "$skip_build" -eq 1 ] && echo none || echo "$derived_data_path")
EOF
