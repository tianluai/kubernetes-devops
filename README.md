# kubernetes-devops

Kubernetes manifests, CI/CD workflows, and infrastructure configuration for the Tianlu AI platform.

## Architecture

Traffic flows through a **single Digital Ocean Load Balancer** created by the **NGINX Ingress Controller**. Host-based routing sends visitors to the frontend or backend Service (both `ClusterIP`).

```
                    Cloudflare DNS (optional)
                              │
                              ▼
              ┌───────────────────────────────┐
              │  DO Load Balancer (1 public IP) │
              │  ingress-nginx-controller      │
              └───────────────┬───────────────┘
                              │
         ┌────────────────────┼────────────────────┐
         │                    │                    │
    ai*.tianlu.tech     ai-api*.tianlu.tech       │
         │                    │                    │
         ▼                    ▼                    │
  ┌─────────────┐      ┌─────────────┐           │
  │ tianluai-web │      │ tianluai-api │           │
  │ Service :80  │      │ Service :80  │           │
  └─────────────┘      └──────────────┘           │
```

**Per environment**, Ingress hostnames differ (see overlays):

| Environment | Frontend host              | API host                      |
|-------------|----------------------------|-------------------------------|
| **prod**    | `ai.tianlu.tech`           | `ai-api.tianlu.tech`          |
| **staging** | `ai-staging.tianlu.tech`   | `ai-api-staging.tianlu.tech`  |
| **dev**     | `ai-dev.tianlu.tech`       | `ai-api-dev.tianlu.tech`      |

Use **single-level subdomains** (e.g. `ai-api.tianlu.tech`) so Cloudflare Universal SSL covers them. Avoid `api.ai.tianlu.tech` unless you add an Advanced Certificate for `*.ai.tianlu.tech`.

## Repository Structure

```
kubernetes-devops/
├── .github/workflows/
│   ├── deploy.yml              # Deploy pipeline (push, dispatch, manual)
│   └── setup-cluster.yml       # Ingress + Docker Hub pull secrets
├── base/
│   ├── kustomization.yaml
│   ├── ingress.yaml            # Host routing (prod hostnames in base)
│   ├── dockerhub-secret.yaml
│   ├── backend/                # Deployment, ClusterIP Service, ConfigMap, Secret
│   └── frontend/
├── overlays/dev|staging|prod/  # Namespace + patches (including ingress hosts)
└── scripts/create-cluster.sh
```

## Prerequisites

- [doctl](https://docs.digitalocean.com/reference/doctl/)
- [kubectl](https://kubernetes.io/docs/tasks/tools/)
- Docker Hub account
- GitHub PAT for cross-repo dispatch (backend/frontend → this repo)

## Initial Setup

### 1. Create the cluster

```bash
doctl auth init
./scripts/create-cluster.sh
```

Or create a cluster in the DO UI. Note the cluster name and set `DIGITALOCEAN_CLUSTER_NAME` in `.github/workflows/deploy.yml` and `setup-cluster.yml` if it differs from `tianlu-k8s`.

### 2. Install Ingress + secrets

Run **Setup Cluster Infrastructure** in GitHub Actions:

- **`install-ingress-nginx`** — installs NGINX Ingress (DO LoadBalancer + public IP)
- **`setup-docker-secret`** — Docker Hub pull secret in all app namespaces
- **`full-setup`** — both

After Ingress is up, get the **external IP**:

```bash
kubectl get svc -n ingress-nginx ingress-nginx-controller
```

### 3. Cloudflare DNS

Create **A** records (Proxied) pointing to that **same** IP for each hostname you use, for example:

| Type | Name (in Cloudflare) | Content   |
|------|------------------------|-----------|
| A    | `ai`                   | Ingress IP |
| A    | `ai-api`               | Ingress IP |

Repeat for staging/dev names (`ai-staging`, `ai-api-staging`, etc.) if you use those environments.

Set **SSL/TLS → Full** (browser ↔ Cloudflare encrypted; Cloudflare ↔ origin can be HTTP).

### 4. Frontend build-time API URL (important)

Next.js inlines `NEXT_PUBLIC_*` at **Docker build** time. Set the GitHub Actions secret **`NEXT_PUBLIC_API_URL`** in the **frontend repo** to match the API URL for that deployment (e.g. `https://ai-api.tianlu.tech` for production). The ConfigMap in this repo documents the target URL; the running bundle must be built with the same value.

### 5. GitHub Secrets

**All three repos:** `DOCKERHUB_USERNAME`, `DOCKERHUB_TOKEN`

**Backend & frontend:** `K8S_DEVOPS_PAT` (repo scope for kubernetes-devops)

**Frontend CI:** `NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY`, `NEXT_PUBLIC_API_URL` (must match deployed API), optional Sentry vars

**kubernetes-devops:** `DIGITALOCEAN_ACCESS_TOKEN`

### 6. Overlay secrets

Replace placeholders in `overlays/<env>/patches/*-secrets.yaml`.

### 7. Deploy

```bash
kubectl kustomize overlays/prod | kubectl apply -f -
```

## CI/CD Flow

Pushes to `main` on backend/frontend build Docker images, dispatch updates image tags here, then this repo applies manifests to DOKS.

## Troubleshooting

```bash
kubectl get pods -n tianluai-prod
kubectl logs -f deployment/tianluai-api -n tianluai-prod
kubectl describe pod <pod-name> -n tianluai-prod
kubectl get svc -n tianluai-prod
kubectl get ingress -n tianluai-prod
kubectl rollout restart deployment/tianluai-api -n tianluai-prod
```

If Ingress returns 404, confirm `kubectl get ingress -n <ns>` shows the correct hosts and that DNS points to the Ingress LoadBalancer IP.
