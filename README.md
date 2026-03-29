# kubernetes-devops

Kustomize manifests and GitHub Actions for Tianlu AI on DigitalOcean Kubernetes (DOKS). App repos build images, push to **DigitalOcean Container Registry (DOCR)**, and send `repository_dispatch` here; this repo updates overlay image tags and applies manifests.

## Traffic

NGINX Ingress (one DO Load Balancer) routes by host to `tianluai-web` and `tianluai-api` (`ClusterIP`).

| Environment | Frontend host            | API host                     |
|-------------|--------------------------|------------------------------|
| prod        | `ai.tianlu.tech`         | `ai-api.tianlu.tech`         |
| staging     | `ai-staging.tianlu.tech` | `ai-api-staging.tianlu.tech` |

## Layout

```
.github/workflows/
  deploy.yml        — validate on PR; apply on dispatch / manual; push to main on overlay changes
  setup-cluster.yml — ingress-nginx, DOCR pull secret per namespace
base/, overlays/{staging,prod}/
```

## One-time setup

1. **DO**: Kubernetes cluster (name matches `CLUSTER_NAME` in workflows, default `tianlu-k8s`), Container Registry (slug matches image prefix, e.g. `registry.digitalocean.com/<slug>/…`).
2. **GitHub Actions → Setup cluster**: run `install-ingress`, then `docr-pull-secret` (or `full`). Point DNS A records at the Ingress external IP.
3. **Secrets (CI / cluster)**
   - **kubernetes-devops (repo):** `DIGITALOCEAN_ACCESS_TOKEN`, `GH_PAT_DEVOPS_TOKEN` (write, for manifest commits), `DOCR_REGISTRY_NAME` (for `doctl registry kubernetes-manifest` in setup).
   - **Runtime Kubernetes secrets** (`backend-secrets`, `frontend-secrets`): **not** applied by `deploy.yml`. Create or update them yourself (`kubectl`, Sealed Secrets, External Secrets, etc.); see `overlays/prod/*-secrets.example.yaml` as a template.
   - **App repos (tianluai_api / tianluai-web):** `DIGITALOCEAN_ACCESS_TOKEN`, `DOCR_REGISTRY`, `GH_PAT_DEVOPS_TOKEN` for CI and `repository_dispatch` to kubernetes-devops. **tianluai-web** also uses `NEXT_PUBLIC_SENTRY_DSN` and optional `SENTRY_ORG`, `SENTRY_PROJECT`, `SENTRY_AUTH_TOKEN` at **Docker build** (repository secrets).
4. **Sentry (Next.js):** `NEXT_PUBLIC_SENTRY_DSN` and optional `SENTRY_ORG`, `SENTRY_PROJECT`, `SENTRY_AUTH_TOKEN` are **build-time** in tianluai-web (Docker `ARG` / CI `build-args`), not injected by kubernetes-devops at deploy — the client bundle is baked when the image is built.
5. **Frontend:** `NEXT_PUBLIC_*` is baked at image build time in tianluai-web; the web pod’s server-side Clerk key is mounted via **`frontend-secrets`** (same value as the API if you use one Clerk app).
6. **Where secrets live (mental model):** `deploy.yml` applies **Kustomize manifests only** (Deployments, Services, ConfigMaps, Ingress, …). **Kubernetes `Secret` objects** in each namespace are maintained outside this workflow unless you add another mechanism.

## Flow

`main` on backend/frontend → tests → version bump → `doctl registry login` → push `…/tianluai-api` or `…/tianluai-web` → `repository_dispatch` (`deploy-backend` / `deploy-frontend`) → this repo patches `overlays/<env>/patches/*-deployment.yaml`, commits, `kubectl apply`, rollout wait.

## Local apply

```bash
kubectl kustomize overlays/prod | kubectl apply -f -
```

## Troubleshooting

```bash
kubectl get pods -n tianluai-prod
kubectl logs -f deployment/tianluai-api -n tianluai-prod
kubectl describe pod -n tianluai-prod -l app=tianluai-api
kubectl get ingress -n tianluai-prod
```

If pods show `ImagePullBackOff`, confirm DOCR pull secret exists in the namespace (`registry-<slug>`) and image names match `registry.digitalocean.com/<slug>/…`.
