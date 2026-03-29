#!/usr/bin/env bash
# Sync backend-secrets and frontend-secrets from GitHub Environment secrets (deploy.yml).
# Required env: K8S_NAMESPACE, MONGODB_URI, CLERK_SECRET_KEY
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
require CLERK_SECRET_KEY

NS="$K8S_NAMESPACE"
SENTRY_DSN_VALUE="${SENTRY_DSN:-}"

kubectl -n "$NS" create secret generic backend-secrets \
  --from-literal=MONGODB_URI="${MONGODB_URI}" \
  --from-literal=CLERK_SECRET_KEY="${CLERK_SECRET_KEY}" \
  --from-literal=SENTRY_DSN="${SENTRY_DSN_VALUE}" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl -n "$NS" create secret generic frontend-secrets \
  --from-literal=CLERK_SECRET_KEY="${CLERK_SECRET_KEY}" \
  --dry-run=client -o yaml | kubectl apply -f -
