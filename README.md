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

**Secrets wiring (like `valueFrom.secretKeyRef`):** Deployments in **`base/`** list each sensitive env var explicitly — **`env[].valueFrom.secretKeyRef`** pointing at **`backend-secrets`** / **`frontend-secrets`**. Only **key names** and **secret names** live in git; **values** come from GitHub Environment secrets (see `deploy.yml` + `scripts/ensure-k8s-secrets.sh`) or from a local `kubectl apply` of `*-secrets.example.yaml` copies. Non-secret config stays in **ConfigMaps** (`envFrom`).

## One-time setup

1. **DO**: Kubernetes cluster (name matches `CLUSTER_NAME` in workflows, default `tianlu-k8s`), Container Registry (slug matches image prefix, e.g. `registry.digitalocean.com/<slug>/…`).
2. **GitHub Actions → Setup cluster**: run `install-ingress`, then `docr-pull-secret` (or `full`). Point DNS A records at the Ingress external IP.
3. **Secrets (CI / cluster)**
   - **kubernetes-devops (repo):** `DIGITALOCEAN_ACCESS_TOKEN`, `GH_PAT_DEVOPS_TOKEN` (write, for manifest commits), `DOCR_REGISTRY_NAME` (for `doctl registry kubernetes-manifest` in setup).
   - **GitHub Environments** `staging` / `prod` — **`MONGODB_URI`**, **`CLERK_SECRET_KEY`**, optional **`SENTRY_DSN`**. The **`deploy.yml`** job (`dispatch-deploy` / `manual-deploy`) runs **`scripts/ensure-k8s-secrets.sh`** so every deploy syncs **`backend-secrets`** and **`frontend-secrets`** in the cluster — no plaintext secrets in git.
   - **Templates in repo:** `overlays/{staging,prod}/*-secrets.example.yaml` are **committed** (placeholders only). New developers use them as the shape of the Secret; **filled** files should be named `*-secrets.local.yaml` (see `.gitignore`) and **never committed**. Prefer **GitHub Environment secrets** + pipeline; use local apply only for emergencies.
   - **App repos (tianluai_api / tianluai-web):** `DIGITALOCEAN_ACCESS_TOKEN`, `DOCR_REGISTRY`, `GH_PAT_DEVOPS_TOKEN` for CI and `repository_dispatch` to kubernetes-devops. **tianluai-web** also uses `NEXT_PUBLIC_SENTRY_DSN` and optional `SENTRY_ORG`, `SENTRY_PROJECT`, `SENTRY_AUTH_TOKEN` at **Docker build** (repository secrets).
4. **Sentry (Next.js):** `NEXT_PUBLIC_SENTRY_DSN` and optional `SENTRY_ORG`, `SENTRY_PROJECT`, `SENTRY_AUTH_TOKEN` are **build-time** in tianluai-web (Docker `ARG` / CI `build-args`), not injected by kubernetes-devops at deploy — the client bundle is baked when the image is built.
5. **Frontend:** `NEXT_PUBLIC_*` is baked at image build time in tianluai-web; the web pod’s server-side Clerk key is mounted via **`frontend-secrets`** (same value as the API if you use one Clerk app).
6. **Where secrets live (mental model):** **GitHub Environment secrets** → **`deploy.yml`** → Kubernetes **`Secret`** objects. Kustomize manifests **do not** embed secret values.

## New developer (runtime secrets)

1. **Normal path:** Get access to **kubernetes-devops** repo settings → **Environments** → add or edit **`MONGODB_URI`**, **`CLERK_SECRET_KEY`**, **`SENTRY_DSN`** for `staging` / `prod`. No local secret files; **run Deploy workflow** (or wait for app `repository_dispatch`) to sync the cluster.
2. **Emergency / local `kubectl`:** Copy **`overlays/<env>/*-secrets.example.yaml`** to **`backend-secrets.local.yaml`** / **`frontend-secrets.local.yaml`** (gitignored), replace placeholders, `kubectl apply -f …`. Never commit filled files.

## Flow

`main` on backend/frontend → tests → version bump → `doctl registry login` → push `…/tianluai-api` or `…/tianluai-web` → `repository_dispatch` (`deploy-backend` / `deploy-frontend`) → this repo patches `overlays/<env>/patches/*-deployment.yaml`, commits, `kubectl apply` (manifests + runtime secrets from GitHub Environment), rollout restart, rollout wait.

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

If pods show `ImagePullBackOff` / **`401 Unauthorized`** pulling from `registry.digitalocean.com`, the namespace is missing a valid **DOCR image pull secret**. Deployments expect **`registry-tianluai`** (see `base/*/deployment.yaml`). Create or refresh it: run the **Setup cluster** workflow with **`docr-pull-secret`** or **`full`**, or locally: `doctl registry kubernetes-manifest "$DOCR_REGISTRY_NAME" --namespace tianluai-staging | kubectl apply -f -` (same for `tianluai-prod`). Ensure **`DOCR_REGISTRY_NAME`** in GitHub matches your registry slug. Confirm with `kubectl get secret registry-tianluai -n tianluai-staging`.

If **`manual-deploy` / `dispatch-deploy` times out** on `kubectl rollout status`, the API or web pod is not becoming Ready. Typical causes: missing **`backend-secrets`** / **`frontend-secrets`**, bad **`MONGODB_URI`**, readiness probes failing, or **`FailedScheduling` / Insufficient cpu** on a single small node (prod + staging + system pods). Staging overlays use modest **requests** and **`maxSurge: 0`** so rollouts do not briefly double pods; if it still does not fit, add a node, scale other workloads down, or lower requests further.

The workflow prints pods, events, describe, and logs in a **Debug** group when rollout fails. Create secrets from `overlays/prod/*-secrets.example.yaml` (or your own manifests) if needed.
