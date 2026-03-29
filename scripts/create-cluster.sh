#!/usr/bin/env bash
set -euo pipefail

# Configuration
CLUSTER_NAME="tianlu-k8s"
REGION="nyc1"
NODE_SIZE="s-2vcpu-4gb"
NODE_COUNT=3
K8S_VERSION="latest"

echo "==> Creating DOKS cluster: ${CLUSTER_NAME}"
doctl kubernetes cluster create "${CLUSTER_NAME}" \
  --region "${REGION}" \
  --size "${NODE_SIZE}" \
  --count "${NODE_COUNT}" \
  --version "${K8S_VERSION}" \
  --auto-upgrade \
  --surge-upgrade \
  --wait

echo "==> Saving kubeconfig"
doctl kubernetes cluster kubeconfig save "${CLUSTER_NAME}"

echo "==> Cluster nodes:"
kubectl get nodes

echo ""
echo "Cluster '${CLUSTER_NAME}' is ready."
echo "Next steps:"
echo "  1. Run the 'Setup Cluster Infrastructure' workflow with 'full-setup'"
echo "  2. Point DNS records to the Load Balancer IP"
echo "  3. Deploy with 'kubectl kustomize overlays/staging | kubectl apply -f -' (or overlays/prod)"
