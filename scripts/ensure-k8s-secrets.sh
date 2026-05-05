#!/usr/bin/env bash
# Sync backend-secrets and frontend-secrets from GitHub Environment secrets (deploy-production / deploy-staging workflows).
# Required env: K8S_NAMESPACE, MONGODB_URI, AUTH_JWT_SECRET, AUTH_SECRET, AUTH_GOOGLE_ID, AUTH_GOOGLE_SECRET, CREDENTIALS_ENCRYPTION_KEYS
# Optional: SENTRY_DSN (empty = disabled in Nest)
set -euo pipefail

require() {
  local name="$1"
  local val="${!name:-}"
  if [ -z "$val" ]; then
    echo "::error::${name} is required — add it to GitHub → Settings → Environments → (staging|prod) → Environment secrets" >&2
    echo "::error::For CREDENTIALS_ENCRYPTION_KEYS use: v1:\$(openssl rand -base64 32) (same format as local tianluai_api .env)." >&2
    exit 1
  fi
}

# GitHub UI paste can add leading/trailing whitespace; Nest treats whitespace-only as unset and crash-loops.
trim_inplace() {
  local name="$1"
  local raw="${!name:-}"
  printf -v "${name}" '%s' "$(printf '%s' "$raw" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
}

for _secret_name in K8S_NAMESPACE MONGODB_URI AUTH_JWT_SECRET AUTH_SECRET AUTH_GOOGLE_ID AUTH_GOOGLE_SECRET CREDENTIALS_ENCRYPTION_KEYS; do
  trim_inplace "${_secret_name}"
done
unset _secret_name

require K8S_NAMESPACE
require MONGODB_URI
require AUTH_JWT_SECRET
require AUTH_SECRET
require AUTH_GOOGLE_ID
require AUTH_GOOGLE_SECRET
require CREDENTIALS_ENCRYPTION_KEYS

NS="$K8S_NAMESPACE"
SENTRY_DSN_VALUE="$(printf '%s' "${SENTRY_DSN:-}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"

kubectl -n "$NS" create secret generic backend-secrets \
  --from-literal=MONGODB_URI="${MONGODB_URI}" \
  --from-literal=AUTH_JWT_SECRET="${AUTH_JWT_SECRET}" \
  --from-literal=SENTRY_DSN="${SENTRY_DSN_VALUE}" \
  --from-literal=CREDENTIALS_ENCRYPTION_KEYS="${CREDENTIALS_ENCRYPTION_KEYS}" \
  --dry-run=client -o yaml | kubectl apply -f -

verify_backend_credentials_secret() {
  local encoded_payload decoded_payload
  encoded_payload="$(kubectl -n "$NS" get secret backend-secrets -o jsonpath='{.data.CREDENTIALS_ENCRYPTION_KEYS}' 2>/dev/null || true)"
  if [ -z "$encoded_payload" ]; then
    echo "::error::backend-secrets has no data.CREDENTIALS_ENCRYPTION_KEYS after apply (namespace ${NS})." >&2
    exit 1
  fi
  decoded_payload="$(printf '%s' "$encoded_payload" | base64 -d)"
  if [ -z "$decoded_payload" ]; then
    echo "::error::CREDENTIALS_ENCRYPTION_KEYS is empty in the cluster Secret — check GitHub Environment value (not whitespace-only)." >&2
    exit 1
  fi
  case "$decoded_payload" in
  v*:*)
    ;;
  *)
    echo "::error::CREDENTIALS_ENCRYPTION_KEYS must look like v1:<base64-32-bytes> (optional comma-separated versions). Value after sync did not start with v<id>:" >&2
    exit 1
    ;;
  esac
}

verify_backend_credentials_secret

kubectl -n "$NS" create secret generic frontend-secrets \
  --from-literal=AUTH_SECRET="${AUTH_SECRET}" \
  --from-literal=AUTH_GOOGLE_ID="${AUTH_GOOGLE_ID}" \
  --from-literal=AUTH_GOOGLE_SECRET="${AUTH_GOOGLE_SECRET}" \
  --from-literal=AUTH_JWT_SECRET="${AUTH_JWT_SECRET}" \
  --dry-run=client -o yaml | kubectl apply -f -
