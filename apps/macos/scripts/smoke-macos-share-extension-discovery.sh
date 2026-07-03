#!/usr/bin/env bash
set -euo pipefail

macos_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
app_path=""
env_name="dev"
keep_staged=0

usage() {
  cat <<'USAGE'
Usage:
  scripts/smoke-macos-share-extension-discovery.sh --app <path-to-Autonomo AV.app>
    [--env dev|prod] [--keep-staged]

Stages the signed app under a temporary ~/Applications folder, registers the
Share Extension, and verifies that the macOS share service list contains
"Autonomo AV Inbox" for a synthetic PDF. This proves discoverability, not UI
execution of the share sheet.
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
    --keep-staged)
      keep_staged=1
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
source_share_path="$app_path/Contents/PlugIns/Autonomo AV Inbox.appex"

if [ "$env_name" = "prod" ]; then
  app_bundle_id="com.avalsys.autonomoav.mac"
else
  app_bundle_id="com.avalsys.autonomoav.mac.dev"
fi
share_bundle_id="$app_bundle_id.share"

stage_dir="$HOME/Applications/AutonomoAVShareDiscovery-$(date +%Y%m%d%H%M%S)-$$"
stage_app="$stage_dir/Autonomo AV.app"
stage_share_path="$stage_app/Contents/PlugIns/Autonomo AV Inbox.appex"
smoke_file="$stage_dir/share-discovery.pdf"

cleanup() {
  pluginkit -e default -i "$share_bundle_id" >/dev/null 2>&1 || true
  if [ -d "$stage_share_path" ]; then
    pluginkit -r "$stage_share_path" >/dev/null 2>&1 || true
  fi
  if [[ "$source_share_path" == *"/.DerivedData"* || "$source_share_path" == *"/.derived-data/"* ]]; then
    pluginkit -r "$source_share_path" >/dev/null 2>&1 || true
  fi
  if [ -d "$stage_app" ]; then
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
      -u "$stage_app" >/dev/null 2>&1 || true
  fi
  if [ "$keep_staged" -eq 0 ]; then
    rm -rf "$stage_dir"
  else
    printf 'Kept staged app at %s\n' "$stage_dir"
  fi
}
trap cleanup EXIT

"$macos_root/scripts/check-macos-signed-build.sh" --env "$env_name" --app "$app_path" >/dev/null

mkdir -p "$stage_dir"
ditto "$app_path" "$stage_app"
printf '%%PDF-1.4\n1 0 obj\n<< /Type /Catalog >>\nendobj\ntrailer\n<< /Root 1 0 R >>\n%%%%EOF\n' > "$smoke_file"

/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
  -f -R -trusted "$stage_app"
pluginkit -a "$stage_share_path"
pluginkit -e use -i "$share_bundle_id" >/dev/null 2>&1 || true

pluginkit_output="$(pluginkit -m -A -D -v -i "$share_bundle_id" || true)"
if ! printf '%s\n' "$pluginkit_output" | grep -Fq "$stage_share_path"; then
  printf '%s\n' "$pluginkit_output" >&2
  echo "Share extension discovery failed: PlugInKit did not return the staged appex." >&2
  exit 1
fi

service_output="$(
  swift -suppress-warnings -e 'import AppKit
let url = URL(fileURLWithPath: CommandLine.arguments[1])
let services = NSSharingService.sharingServices(forItems: [url])
for service in services {
  print("service title=\(service.title) menu=\(service.menuItemTitle)")
}
let hasAutonomo = services.contains { $0.title == "Autonomo AV Inbox" || $0.menuItemTitle == "Autonomo AV Inbox" }
print("hasAutonomoShareService=\(hasAutonomo)")
' "$smoke_file"
)"

if ! printf '%s\n' "$service_output" | grep -Fq "hasAutonomoShareService=true"; then
  printf '%s\n' "$service_output" >&2
  echo "Share extension discovery failed: Autonomo AV Inbox was not listed for the synthetic PDF." >&2
  exit 1
fi

cat <<EOF
Autonomo AV macOS Share Extension discovery smoke passed.
  environment: $env_name
  app: $app_path
  staged app: $stage_app
  extension id: $share_bundle_id
  share service: Autonomo AV Inbox
  kept staged: $([ "$keep_staged" -eq 1 ] && echo yes || echo no)
EOF
