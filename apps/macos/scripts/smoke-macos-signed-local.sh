#!/usr/bin/env bash
set -euo pipefail

app_path=""
env_name="dev"
allow_signed_in=0
keep_artifacts=0

usage() {
  cat <<'USAGE'
Usage:
  scripts/smoke-macos-signed-local.sh --app <path-to-Autonomo AV.app> [--env dev|prod]
    [--allow-signed-in] [--keep-artifacts]

Runs the local signed macOS smoke set against an already built app:
  - Share Extension PlugInKit registration
  - Share Extension service discovery
  - Finder/Open With no-upload import
  - Services no-upload import

This script does not build, archive, export, upload, or contact App Store
Connect. Build the app first with a repo-local -derivedDataPath.
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

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
app_dir="$(cd "$(dirname "$app_path")" && pwd)"
app_path="$app_dir/$(basename "$app_path")"

optional_flags=()
if [ "$allow_signed_in" -eq 1 ]; then
  optional_flags+=(--allow-signed-in)
fi
if [ "$keep_artifacts" -eq 1 ]; then
  optional_flags+=(--keep-artifacts)
fi

"$script_dir/smoke-macos-share-extension-registration.sh" --env "$env_name" --app "$app_path"
"$script_dir/smoke-macos-share-extension-discovery.sh" --env "$env_name" --app "$app_path"
if [ "${#optional_flags[@]}" -gt 0 ]; then
  "$script_dir/smoke-macos-open-with.sh" --env "$env_name" --app "$app_path" "${optional_flags[@]}"
  "$script_dir/smoke-macos-services.sh" --env "$env_name" --app "$app_path" "${optional_flags[@]}"
else
  "$script_dir/smoke-macos-open-with.sh" --env "$env_name" --app "$app_path"
  "$script_dir/smoke-macos-services.sh" --env "$env_name" --app "$app_path"
fi

cat <<EOF
Autonomo AV macOS local signed smoke set passed.
  environment: $env_name
  app: $app_path
EOF
