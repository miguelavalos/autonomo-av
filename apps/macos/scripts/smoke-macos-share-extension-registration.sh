#!/usr/bin/env bash
set -euo pipefail

macos_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
app_path=""
env_name="dev"
keep_registered=0

usage() {
  cat <<'USAGE'
Usage:
  scripts/smoke-macos-share-extension-registration.sh --app <path-to-Autonomo AV.app>
    [--env dev|prod] [--keep-registered]

Validates the built macOS Share Extension as a signed PlugInKit extension. This
does not execute the share sheet UI or pass a file payload to the extension.
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
    --keep-registered)
      keep_registered=1
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

if [ -z "$app_path" ]; then
  echo "--app is required." >&2
  usage >&2
  exit 2
fi
if [ "$env_name" != "dev" ] && [ "$env_name" != "prod" ]; then
  echo "--env must be dev or prod." >&2
  exit 2
fi
if [ ! -d "$app_path" ]; then
  echo "App bundle not found: $app_path" >&2
  exit 1
fi

app_dir="$(cd "$(dirname "$app_path")" && pwd)"
app_path="$app_dir/$(basename "$app_path")"

if [ "$env_name" = "prod" ]; then
  app_bundle_id="com.avalsys.autonomoav.mac"
else
  app_bundle_id="com.avalsys.autonomoav.mac.dev"
fi
share_bundle_id="$app_bundle_id.share"
share_path="$app_path/Contents/PlugIns/Autonomo AV Inbox.appex"
share_info="$share_path/Contents/Info.plist"

cleanup() {
  if [ "$keep_registered" -eq 0 ] && [ -d "$share_path" ]; then
    pluginkit -r "$share_path" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

plist_print() {
  /usr/libexec/PlistBuddy -c "Print :$2" "$1" 2>/dev/null || true
}

if [ ! -d "$share_path" ]; then
  echo "Share extension not found: $share_path" >&2
  exit 1
fi

"$macos_root/scripts/check-macos-signed-build.sh" --env "$env_name" --app "$app_path" >/dev/null
codesign --verify --deep --strict "$app_path"
codesign --verify --strict "$share_path"

extension_point="$(plist_print "$share_info" "NSExtension:NSExtensionPointIdentifier")"
extension_principal="$(plist_print "$share_info" "NSExtension:NSExtensionPrincipalClass")"
file_count="$(plist_print "$share_info" "NSExtension:NSExtensionAttributes:NSExtensionActivationRule:NSExtensionActivationSupportsFileWithMaxCount")"
image_count="$(plist_print "$share_info" "NSExtension:NSExtensionAttributes:NSExtensionActivationRule:NSExtensionActivationSupportsImageWithMaxCount")"

if [ "$extension_point" != "com.apple.share-services" ]; then
  echo "Share extension point must be com.apple.share-services, got ${extension_point:-<missing>}." >&2
  exit 1
fi
if [ "$extension_principal" != "AutonomoAVMacShareExtension.ShareViewController" ]; then
  echo "Share extension principal class mismatch: ${extension_principal:-<missing>}." >&2
  exit 1
fi
if [ "$file_count" != "10" ] || [ "$image_count" != "10" ]; then
  echo "Share extension activation rule must support up to 10 files and 10 images." >&2
  exit 1
fi

pluginkit -a "$share_path" >/dev/null
pluginkit_output="$(pluginkit -m -A -D -v -i "$share_bundle_id" || true)"
if ! printf '%s\n' "$pluginkit_output" | grep -Fq "$share_bundle_id"; then
  printf '%s\n' "$pluginkit_output" >&2
  echo "Share extension was not returned by PlugInKit for $share_bundle_id." >&2
  exit 1
fi
if ! printf '%s\n' "$pluginkit_output" | grep -Fq "$share_path"; then
  printf '%s\n' "$pluginkit_output" >&2
  echo "PlugInKit returned $share_bundle_id but not the expected appex path." >&2
  exit 1
fi

cat <<EOF
Autonomo AV macOS Share Extension registration smoke passed.
  environment: $env_name
  app: $app_path
  share extension: $share_path
  extension id: $share_bundle_id
  extension point: $extension_point
  registered: yes
  kept registered: $([ "$keep_registered" -eq 1 ] && echo yes || echo no)
EOF
