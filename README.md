# kubernetes-devops

Kubernetes manifests, CI/CD workflows, and infrastructure configuration for the Tianlu AI platform.

## Architecture

```
              ┌──────────────────┐
              │  DO Load Balancer│
              │  (per service)   │
              └──┬────────────┬──┘
                 │            │
        :80 (web)│            │:80 (api)
                 │            │
        ┌────────▼──┐  ┌─────▼───────┐
        │ Frontend   │  │ Backend     │
        │ (Next.js)  │  │ (NestJS)    │
        │ replicas   │  │ replicas    │
        └────────────┘  └──────┬──────┘
                               │
                         ┌─────▼─────┐
                         │  MongoDB   │
                         │ (managed)  │
                         └───────────┘
```

Each service gets its own Digital Ocean Load Balancer with a public IP. When you're ready to add a domain, you can layer in NGINX Ingress + cert-manager on top.

## Repository Structure

```
kubernetes-devops/
├── .github/workflows/
│   ├── deploy.yml              # Main deploy pipeline (push, dispatch, manual)
│   └── setup-cluster.yml       # One-time cluster bootstrap (Docker secret)
├── base/                       # Base Kustomize manifests
│   ├── kustomization.yaml
│   ├── namespace.yaml
│   ├── dockerhub-secret.yaml
│   ├── backend/
│   │   ├── deployment.yaml
│   │   ├── service.yaml        # LoadBalancer type
│   │   ├── configmap.yaml
│   │   ├── secret.yaml
│   │   └── kustomization.yaml
│   └── frontend/
│       ├── deployment.yaml
│       ├── service.yaml        # LoadBalancer type
│       ├── configmap.yaml
│       ├── secret.yaml
│       └── kustomization.yaml
├── overlays/                   # Per-environment patches
│   ├── dev/
│   ├── staging/
│   └── prod/
└── scripts/
    └── create-cluster.sh       # Provision DOKS cluster
```

## Prerequisites

- [doctl](https://docs.digitalocean.com/reference/doctl/) (Digital Ocean CLI)
- [kubectl](https://kubernetes.io/docs/tasks/tools/)
- Docker Hub account
- GitHub Personal Access Token (for cross-repo dispatch)

## Initial Setup

### 1. Create the Digital Ocean Kubernetes Cluster

```bash
doctl auth init
./scripts/create-cluster.sh
```

This creates a 3-node DOKS cluster (`s-2vcpu-4gb` nodes) in `nyc1`.

### 2. Bootstrap Cluster Infrastructure

Run the **Setup Cluster Infrastructure** workflow in GitHub Actions with `full-setup`, or manually:

```bash
# Create namespaces + Docker Hub pull secret
for NS in tianluai-dev tianluai-staging tianluai-prod; do
  kubectl create namespace ${NS} --dry-run=client -o yaml | kubectl apply -f -
  kubectl create secret docker-registry dockerhub-credentials \
    --docker-server=https://index.docker.io/v1/ \
    --docker-username=YOUR_USERNAME \
    --docker-password=YOUR_TOKEN \
    --namespace=${NS} \
    --dry-run=client -o yaml | kubectl apply -f -
done
```

### 3. Configure GitHub Secrets

#### All three repos need:

| Secret               | Description                              |
|----------------------|------------------------------------------|
| `DOCKERHUB_USERNAME` | Docker Hub username                      |
| `DOCKERHUB_TOKEN`    | Docker Hub access token                  |

#### Backend & Frontend repos also need:

| Secret           | Description                                      |
|------------------|--------------------------------------------------|
| `K8S_DEVOPS_PAT` | GitHub PAT with `repo` scope for kubernetes-devops |

#### Frontend repo also needs:

| Secret                             | Description           |
|------------------------------------|-----------------------|
| `NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY`| Clerk publishable key |
| `NEXT_PUBLIC_API_URL`              | Backend API URL       |
| `NEXT_PUBLIC_SENTRY_DSN`          | Sentry DSN (optional) |
| `SENTRY_ORG`                       | Sentry org slug       |
| `SENTRY_PROJECT`                   | Sentry project slug   |
| `SENTRY_AUTH_TOKEN`                | Sentry auth token     |

#### kubernetes-devops repo needs:

| Secret                      | Description                    |
|-----------------------------|--------------------------------|
| `DIGITALOCEAN_ACCESS_TOKEN` | DO API token                   |
| `SLACK_WEBHOOK_URL`         | Slack webhook for notifications|

### 4. Update Secrets in Overlays

Replace `REPLACE_WITH_*` placeholder values in `overlays/<env>/patches/*-secrets.yaml` with real credentials.

### 5. Deploy

```bash
# Dev environment
kubectl kustomize overlays/dev | kubectl apply -f -

# Staging
kubectl kustomize overlays/staging | kubectl apply -f -

# Production
kubectl kustomize overlays/prod | kubectl apply -f -
```

### 6. Get your service IPs

After deploying, each service gets a public IP from Digital Ocean:

```bash
kubectl get svc -n tianluai-dev
```

Use the `EXTERNAL-IP` values to access your frontend and backend directly.

## CI/CD Flow

### Backend (tianluai_api)

```
Push to main/staging/develop
  → Lint & format check
  → Unit & integration tests
  → Build validation
  → Trivy security scan
  → Docker build & push (tagged: SHA, branch, latest)
  → Dispatch to kubernetes-devops
    → Update image tag in overlay
    → Apply manifests to DOKS cluster
```

### Frontend (tianluai-web)

```
Push to main/staging/develop
  → Lint check
  → Unit tests
  → Build validation
  → Trivy security scan
  → Lighthouse audit (PRs only)
  → Docker build & push
  → Dispatch to kubernetes-devops
    → Update image tag in overlay
    → Apply manifests to DOKS cluster
```

### Branch → Environment Mapping

| Branch    | Environment |
|-----------|-------------|
| `develop` | dev         |
| `staging` | staging     |
| `main`    | prod        |

## Environment Resources

| Environment | Replicas | CPU Request | Memory Request |
|-------------|----------|-------------|----------------|
| dev         | 1        | 50m         | 64Mi           |
| staging     | 2        | 100m        | 128Mi          |
| prod        | 3        | 250m        | 256Mi          |

## Adding a Domain Later

When you have a domain, you can add Ingress + TLS support:

1. Install NGINX Ingress Controller: `helm install ingress-nginx ingress-nginx/ingress-nginx`
2. Install cert-manager: `helm install cert-manager jetstack/cert-manager --set crds.enabled=true`
3. Add `base/ingress/` with Ingress + ClusterIssuer manifests
4. Switch services back to `ClusterIP`
5. Point your domain's DNS A records to the Ingress Load Balancer IP

## Troubleshooting

```bash
# Check pod status
kubectl get pods -n tianluai-prod

# View logs
kubectl logs -f deployment/prod-tianluai-api -n tianluai-prod

# Describe a failing pod
kubectl describe pod <pod-name> -n tianluai-prod

# Check service external IPs
kubectl get svc -n tianluai-prod

# Restart a deployment
kubectl rollout restart deployment/prod-tianluai-api -n tianluai-prod
```
