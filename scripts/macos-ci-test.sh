#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MACOS_ROOT="$ROOT_DIR/apps/macos"
DERIVED_DATA_PATH="$ROOT_DIR/.derived-data/macos-ci"
RESULT_BUNDLE_PATH="$DERIVED_DATA_PATH/TestResults/AutonomoAVMac.xcresult"

cleanup() {
  local status=$?
  if [ "$status" -eq 0 ]; then
    if [ -d "$DERIVED_DATA_PATH" ]; then
      du -sh "$DERIVED_DATA_PATH"
      rm -rf "$DERIVED_DATA_PATH"
      rmdir "$ROOT_DIR/.derived-data" 2>/dev/null || true
    fi
  else
    echo "macOS CI failed; preserving derived data at $DERIVED_DATA_PATH" >&2
  fi
}
trap cleanup EXIT

rm -rf "$RESULT_BUNDLE_PATH"
mkdir -p "$(dirname "$RESULT_BUNDLE_PATH")"

cd "$MACOS_ROOT"

xcodegen generate
scripts/check-macos-release-preflight.sh --env dev --configuration Debug --skip-build

xcodebuild test \
  -project AutonomoAVMac.xcodeproj \
  -scheme AutonomoAVMac \
  -destination "platform=macOS" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  -resultBundlePath "$RESULT_BUNDLE_PATH" \
  CODE_SIGNING_ALLOWED=NO
