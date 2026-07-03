#!/usr/bin/env bash
set -euo pipefail

macos_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
app_path=""
env_name="dev"
allow_signed_in=0
keep_artifacts=0

usage() {
  cat <<'USAGE'
Usage:
  scripts/smoke-macos-services.sh --app <path-to-Autonomo AV.app> [--env dev|prod]
    [--allow-signed-in] [--keep-artifacts]

Runs a local signed macOS Services smoke without archiving, exporting, uploading,
or contacting App Store Connect. By default it requires the launched app to
restore signed-out before invoking the service, so the imported synthetic PDF
stays in the isolated local queue and is not uploaded.
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
    --allow-signed-in)
      allow_signed_in=1
      shift
      ;;
    --keep-artifacts)
      keep_artifacts=1
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

smoke_base="$HOME/Library/Containers/$app_bundle_id/Data/tmp/autonomoav-macos-services-smoke-$(date +%Y%m%d%H%M%S)-$$"
smoke_root="$smoke_base/queue"
smoke_file="$smoke_base/service-smoke.pdf"
logs_file="$smoke_base/services-smoke.log"

cleanup() {
  osascript -e "tell application id \"$app_bundle_id\" to quit" >/dev/null 2>&1 || true
  sleep 1
  pkill -x "Autonomo AV" >/dev/null 2>&1 || true
  if [ "$keep_artifacts" -eq 0 ]; then
    rm -rf "$smoke_base"
  else
    printf 'Kept smoke artifacts at %s\n' "$smoke_base"
  fi
}
trap cleanup EXIT

"$macos_root/scripts/check-macos-signed-build.sh" --env "$env_name" --app "$app_path" >/dev/null

mkdir -p "$smoke_root"
printf '%%PDF-1.4\n1 0 obj\n<< /Type /Catalog >>\nendobj\ntrailer\n<< /Root 1 0 R >>\n%%%%EOF\n' > "$smoke_file"

start_stamp="$(date '+%Y-%m-%d %H:%M:%S')"
osascript -e "tell application id \"$app_bundle_id\" to quit" >/dev/null 2>&1 || true
sleep 1
open -n -g --env "AUTONOMOAV_LOCAL_INTAKE_ROOT_URL=$smoke_root" -a "$app_path"

account_state=""
for _ in $(seq 1 20); do
  /usr/bin/log show --start "$start_stamp" --info \
    --predicate "subsystem == \"$app_bundle_id\" && category == \"App\"" \
    > "$logs_file" 2>/dev/null || true

  if grep -Fq "Account restore resolved signed-in user" "$logs_file"; then
    account_state="signed-in"
    break
  fi
  if grep -Fq "Account restore completed without signed-in user" "$logs_file"; then
    account_state="signed-out"
    break
  fi
  sleep 1
done

if [ "$account_state" = "signed-in" ] && [ "$allow_signed_in" -eq 0 ]; then
  echo "App restored a signed-in account. Re-run with --allow-signed-in only when upload/backend mutation is intentional." >&2
  exit 1
fi
if [ "$account_state" != "signed-out" ] && [ "$allow_signed_in" -eq 0 ]; then
  echo "Could not prove signed-out account state from unified logs; refusing no-upload Services smoke." >&2
  exit 1
fi

/System/Library/CoreServices/pbs -read_bundle "$app_path" >/dev/null 2>&1 || true

service_output="$(
  swift -e 'import AppKit
let serviceName = "Send to Autonomo AV"
let path = CommandLine.arguments[1]
let pasteboard = NSPasteboard(name: NSPasteboard.Name("AutonomoAVServiceSmoke-\(UUID().uuidString)"))
pasteboard.clearContents()
let didWrite = pasteboard.writeObjects([URL(fileURLWithPath: path) as NSURL])
let didPerform = NSPerformService(serviceName, pasteboard)
print("pasteboardWrite=\(didWrite)")
print("servicePerformed=\(didPerform)")
' "$smoke_file"
)"

if ! printf '%s\n' "$service_output" | grep -Fq "pasteboardWrite=true"; then
  printf '%s\n' "$service_output" >&2
  echo "Service smoke failed: could not write file URL pasteboard." >&2
  exit 1
fi
if ! printf '%s\n' "$service_output" | grep -Fq "servicePerformed=true"; then
  printf '%s\n' "$service_output" >&2
  echo "Service smoke failed: NSPerformService did not invoke Send to Autonomo AV." >&2
  exit 1
fi

for _ in $(seq 1 20); do
  if [ -f "$smoke_root/intake-items.json" ]; then
    break
  fi
  sleep 1
done

if [ ! -f "$smoke_root/intake-items.json" ]; then
  echo "Service smoke failed: missing intake-items.json at $smoke_root/intake-items.json" >&2
  exit 1
fi

node -e '
const fs = require("node:fs");
const itemsPath = process.argv[1];
const expectedName = process.argv[2];
const items = JSON.parse(fs.readFileSync(itemsPath, "utf8"));
const match = items.find((item) =>
  item.source === "macos_service" &&
  item.status === "pending" &&
  item.mimeType === "application/pdf" &&
  item.fileName === expectedName
);
if (!match) {
  console.error(`Service smoke failed: expected pending macos_service PDF item in ${itemsPath}`);
  console.error(JSON.stringify(items, null, 2));
  process.exit(1);
}
console.log(`Service smoke queue item: id=${match.id} source=${match.source} status=${match.status} bytes=${match.byteSize}`);
' "$smoke_root/intake-items.json" "service-smoke.pdf"

/usr/bin/log show --start "$start_stamp" --info \
  --predicate "subsystem == \"$app_bundle_id\" && (category == \"Services\" || category == \"Intake\" || category == \"App\")" \
  > "$logs_file" 2>/dev/null || true

if ! grep -Fq "Services request accepted count=1" "$logs_file"; then
  echo "Service smoke failed: missing Services acceptance log." >&2
  exit 1
fi
if [ "$account_state" = "signed-out" ] && ! grep -Fq "Upload pending blocked: signed out" "$logs_file"; then
  echo "Service smoke failed: signed-out no-upload guard was not observed." >&2
  exit 1
fi

cat <<EOF
Autonomo AV macOS Services smoke passed.
  environment: $env_name
  account state: $account_state
  app: $app_path
  intake root: $smoke_root
EOF
