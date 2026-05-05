#!/usr/bin/env bash
# Fail if the live tianluai-api Deployment does not mount CREDENTIALS_ENCRYPTION_KEYS
# from backend-secrets (without it Nest crash-loops — see CredentialsCryptoService).
#
# Usage: K8S_NAMESPACE=tianluai-prod bash scripts/assert-api-deployment-has-credentials-env.sh
set -euo pipefail

NS="${K8S_NAMESPACE:?Set K8S_NAMESPACE (e.g. tianluai-prod)}"

if ! names=$(kubectl get deployment tianluai-api -n "$NS" -o jsonpath='{.spec.template.spec.containers[0].env[*].name}' 2>/dev/null); then
  echo "::error::kubectl could not read deployment tianluai-api in namespace ${NS}." >&2
  exit 1
fi

if [ -z "$names" ]; then
  echo "::error::tianluai-api has no explicit env entries — manifest out of date?" >&2
  exit 1
fi

if ! tr ' ' '\n' <<<"$names" | grep -Fqx CREDENTIALS_ENCRYPTION_KEYS; then
  echo "::error::Deployment tianluai-api in ${NS} is missing env CREDENTIALS_ENCRYPTION_KEYS (secretKeyRef → backend-secrets)." >&2
  echo "::error::Apply current kubernetes-devops manifests: kubectl kustomize overlays/<env> | kubectl apply -f -" >&2
  echo "Got env names (space-separated): ${names}" >&2
  exit 1
fi

echo "OK: tianluai-api declares CREDENTIALS_ENCRYPTION_KEYS in ${NS}"
