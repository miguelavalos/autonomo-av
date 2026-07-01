#!/usr/bin/env bash
set -euo pipefail

environment="${1:-}"

case "$environment" in
  preview)
    web_origin="https://autonomo-av-preview.avalsys.com"
    account_origin="https://account-av-preview.avalsys.com"
    api_base_url="https://api-account-av-preview.avalsys.com"
    ;;
  production)
    web_origin="https://autonomo-av.avalsys.com"
    account_origin="https://account-av.avalsys.com"
    api_base_url="https://api-account-av.avalsys.com"
    ;;
  *)
    echo "usage: bash ./scripts/build-cloudflare.sh <preview|production>" >&2
    exit 2
    ;;
esac

export VITE_AUTONOMOAV_USE_FIXTURES=false
export VITE_AUTONOMOAV_DEV_BEARER_TOKEN=""
export VITE_AUTONOMOAV_EMAIL_INTAKE_ENABLED=false
export VITE_AUTONOMOAV_EMAIL_ALIAS=""
export VITE_AUTONOMOAV_API_BASE_URL="$api_base_url"
export VITE_ACCOUNTAV_API_BASE_URL="$api_base_url"
export VITE_ACCOUNTAV_MANAGEMENT_URL="$account_origin"
export VITE_AUTONOMOAV_DELETE_ACCOUNT_URL="$web_origin/delete-account"
export VITE_AUTONOMOAV_PRIVACY_URL="$web_origin/privacy"
export VITE_AUTONOMOAV_TERMS_URL="$web_origin/terms"

if [[ -z "${VITE_ACCOUNTAV_PUBLISHABLE_KEY:-}" ]]; then
  echo "VITE_ACCOUNTAV_PUBLISHABLE_KEY is not set; signed-in routes will show live auth missing."
fi

vite build
