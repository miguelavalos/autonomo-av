#!/usr/bin/env bash
set -euo pipefail

macos_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
pbxproj="$macos_root/AutonomoAVMac.xcodeproj/project.pbxproj"

if [ ! -f "$pbxproj" ]; then
  echo "Xcode project not found: $pbxproj" >&2
  exit 1
fi

# XcodeGen 2.45.4 serializes nested TargetAttributes dictionaries as a string.
# Normalize the App Groups capability back to the PBX dictionary form Xcode uses.
perl -0pi -e '
  s/\QSystemCapabilities = "[\"com.apple.ApplicationGroups.Mac\": [\"enabled\": 1]]";\E/SystemCapabilities = {\n\t\t\t\t\t\t\tcom.apple.ApplicationGroups.Mac = {\n\t\t\t\t\t\t\t\tenabled = 1;\n\t\t\t\t\t\t\t};\n\t\t\t\t\t\t};/g
' "$pbxproj"

if grep -Fq 'SystemCapabilities = "[\"com.apple.ApplicationGroups.Mac\": [\"enabled\": 1]]";' "$pbxproj"; then
  echo "Failed to normalize XcodeGen SystemCapabilities placeholder." >&2
  exit 1
fi
