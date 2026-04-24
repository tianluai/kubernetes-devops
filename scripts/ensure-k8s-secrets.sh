#!/usr/bin/env bash
# Sync backend-secrets and frontend-secrets from GitHub Environment secrets (deploy-production / deploy-staging workflows).
# Required env: K8S_NAMESPACE, MONGODB_URI, AUTH_JWT_SECRET, AUTH_SECRET, AUTH_GOOGLE_ID, AUTH_GOOGLE_SECRET
# Optional: SENTRY_DSN (empty = disabled in Nest)
set -euo pipefail

require() {
  local name="$1"
  local val="${!name:-}"
  if [ -z "$val" ]; then
    echo "::error::${name} is required — add it to GitHub → Settings → Environments → (staging|prod) → Environment secrets" >&2
    exit 1
  fi
}

require K8S_NAMESPACE
require MONGODB_URI
require AUTH_JWT_SECRET
require AUTH_SECRET
require AUTH_GOOGLE_ID
require AUTH_GOOGLE_SECRET

NS="$K8S_NAMESPACE"
SENTRY_DSN_VALUE="${SENTRY_DSN:-}"

kubectl -n "$NS" create secret generic backend-secrets \
  --from-literal=MONGODB_URI="${MONGODB_URI}" \
  --from-literal=AUTH_JWT_SECRET="${AUTH_JWT_SECRET}" \
  --from-literal=SENTRY_DSN="${SENTRY_DSN_VALUE}" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl -n "$NS" create secret generic frontend-secrets \
  --from-literal=AUTH_SECRET="${AUTH_SECRET}" \
  --from-literal=AUTH_GOOGLE_ID="${AUTH_GOOGLE_ID}" \
  --from-literal=AUTH_GOOGLE_SECRET="${AUTH_GOOGLE_SECRET}" \
  --from-literal=AUTH_JWT_SECRET="${AUTH_JWT_SECRET}" \
  --dry-run=client -o yaml | kubectl apply -f -
