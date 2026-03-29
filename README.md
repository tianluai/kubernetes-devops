# kubernetes-devops

Kustomize manifests and GitHub Actions for Tianlu AI on DigitalOcean Kubernetes (DOKS). App repos build images, push to **DigitalOcean Container Registry (DOCR)**, and send `repository_dispatch` here; this repo updates overlay image tags and applies manifests.

## Traffic

NGINX Ingress (one DO Load Balancer) routes by host to `tianluai-web` and `tianluai-api` (`ClusterIP`).

| Environment | Frontend host            | API host                     |
|-------------|--------------------------|------------------------------|
| prod        | `ai.tianlu.tech`         | `ai-api.tianlu.tech`         |
| staging     | `ai-staging.tianlu.tech` | `ai-api-staging.tianlu.tech` |
| dev         | `ai-dev.tianlu.tech`     | `ai-api-dev.tianlu.tech`     |

## Layout

```
.github/workflows/
  deploy.yml        — validate on PR; apply on dispatch / manual; push to main on overlay changes
  setup-cluster.yml — ingress-nginx, DOCR pull secret per namespace
base/, overlays/{dev,staging,prod}/
```

## One-time setup

1. **DO**: Kubernetes cluster (name matches `CLUSTER_NAME` in workflows, default `tianlu-k8s`), Container Registry (slug matches image prefix, e.g. `registry.digitalocean.com/<slug>/…`).
2. **GitHub Actions → Setup cluster**: run `install-ingress`, then `docr-pull-secret` (or `full`). Point DNS A records at the Ingress external IP.
3. **Secrets**
   - **kubernetes-devops:** `DIGITALOCEAN_ACCESS_TOKEN`, `GH_PAT_DEVOPS_TOKEN` (contents: write, to push manifest commits), `DOCR_REGISTRY_NAME` (registry slug for `doctl registry kubernetes-manifest`).
   - **tianluai_api / tianluai-web:** `DIGITALOCEAN_ACCESS_TOKEN`, `DOCR_REGISTRY` (full host + registry path, e.g. `registry.digitalocean.com/tianluai`), `GH_PAT_DEVOPS_TOKEN` (repo dispatch to kubernetes-devops + push for version bumps).
4. **Frontend:** `NEXT_PUBLIC_API_URL` and Clerk/Sentry secrets as needed; Next.js bakes `NEXT_PUBLIC_*` at image build time.
5. Replace placeholders in `overlays/<env>/patches/*-secrets.yaml`.

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
