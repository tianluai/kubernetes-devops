# kubernetes-devops

Kustomize manifests and GitHub Actions for Tianlu AI on DigitalOcean Kubernetes (DOKS). App repos build images, push to **DigitalOcean Container Registry (DOCR)**, and send `repository_dispatch` here; this repo updates overlay image tags and applies manifests.

## Traffic

NGINX Ingress (one DO Load Balancer) routes by host to `tianluai-web` and `tianluai-api` (`ClusterIP`).

| Environment | Frontend host            | API host                     |
|-------------|--------------------------|------------------------------|
| prod        | `ai.tianlu.tech`         | `ai-api.tianlu.tech`         |
| staging     | `ai-staging.tianlu.tech` | `ai-api-staging.tianlu.tech` |

**DNS names must match the table.** In Cloudflare, point **`ai`**, **`ai-api`**, **`ai-staging`**, and **`ai-api-staging`** at the Ingress load balancer IP (FQDNs as in the table).

### Cloudflare SSL (error 526) — free options

Visitors hit **Cloudflare** (HTTPS, Universal SSL — free). Cloudflare then connects to your **origin** (the DO load balancer / NGINX Ingress). **Error 526** means Cloudflare is using **Full (strict)** and the origin is not presenting a certificate it trusts (often the Ingress default fake cert, or HTTP-only).

You do **not** need to buy a certificate. Pick one:

1. **Cloudflare Origin Certificate (simplest with orange-cloud proxy)** — free in Cloudflare: **SSL/TLS → Origin Server → Create certificate**. Include the hostnames for that environment (e.g. prod: `ai.tianlu.tech`, `ai-api.tianlu.tech`; staging: `ai-staging.tianlu.tech`, `ai-api-staging.tianlu.tech`). Save the PEM + private key, then create the Kubernetes secret the Ingress already references:

   ```bash
   kubectl create secret tls tianluai-tls \
     --cert=origin.pem --key=origin.key \
     -n tianluai-prod
   # Staging (same cert if it lists staging hostnames too, or a second Origin cert):
   kubectl create secret tls tianluai-tls \
     --cert=origin-staging.pem --key=origin-staging.key \
     -n tianluai-staging
   ```

   Re-apply manifests (or restart nothing if the Ingress already points at `tianluai-tls`). Keep **SSL/TLS mode** on **Full (strict)**.

2. **cert-manager + Let’s Encrypt** — free public certificates on the cluster (often **HTTP-01** or **DNS-01** with a Cloudflare API token). More moving parts; good if you want automated renewal without Origin CA.

3. **Temporary / not recommended long-term:** set Cloudflare **SSL/TLS** to **Full** (not *Full (strict)*). Cloudflare accepts the Ingress default/self-signed cert. No secret setup, but origin validation is weaker than (1) or (2).

## Layout

```
.github/workflows/
  ci.yml              — kustomize validate on PR/push
  deploy-production.yml / deploy-staging.yml — apply on repository_dispatch or manual
  setup-cluster.yml   — ingress-nginx, DOCR pull secret per namespace
base/, overlays/{staging,prod}/
```

**Secrets wiring (like `valueFrom.secretKeyRef`):** Deployments in **`base/`** list each sensitive env var explicitly — **`env[].valueFrom.secretKeyRef`** pointing at **`backend-secrets`** / **`frontend-secrets`**. Only **key names** and **secret names** live in git; **values** come from GitHub Environment secrets (see deploy workflows + `scripts/ensure-k8s-secrets.sh`) or from a local `kubectl apply` of `*-secrets.example.yaml` copies. Non-secret config stays in **ConfigMaps** (`envFrom`).

### GitHub secrets: which repo needs what

GitHub **does not share** secrets between repositories. **Do not** put tokens only in **kubernetes-devops** and expect **tianluai-web** / **tianluai_api** workflows to see them.

| Secret | **kubernetes-devops** repo | **tianluai-web** / **tianluai_api** repos |
|--------|----------------------------|-------------------------------------------|
| **`GH_PAT_DEVOPS_TOKEN`** | Yes — workflows **commit** manifest updates back to this repo (`git push`). | Yes — workflows **call** `repository_dispatch` **into** this repo (needs `repo` scope on the PAT). Same token value is fine; **add the secret in each repo** (or per-repo Environment `prod` / `staging` on the app side). |
| **`DIGITALOCEAN_ACCESS_TOKEN`** | Yes — `doctl` / `kubectl apply`. | Yes — `doctl registry login` when building and pushing images. |
| **`DOCR_REGISTRY`** | **No** — image URLs are passed in the **dispatch payload** from app CI. | Yes — full registry prefix, e.g. `registry.digitalocean.com/your-registry-name` (no trailing slash). |
| **`DOCR_REGISTRY_NAME`** | Yes — **Setup cluster** workflow only (registry slug for pull-secret manifest). | No. |
| **`MONGODB_URI`**, **`CLERK_SECRET_KEY`**, **`SENTRY_DSN`** | Yes — **Environment** `staging` / `prod` — synced to cluster by `ensure-k8s-secrets.sh`. | Not in kubernetes-devops unless you duplicate for something else. |

**App repos** (`tianluai-web`, `tianluai_api`): jobs that use **Environment** secrets (`build-check`, `docker`, `deploy`) must declare **`environment: prod`** or **`environment: staging`** (see those workflows). Otherwise `secrets.*` only resolves **repository** secrets, not Environment secrets.

**Protection rules:** If an Environment has **required reviewers**, jobs that set `environment:` on that Environment will wait for approval before continuing.

## One-time setup

1. **DO**: Kubernetes cluster (name matches `CLUSTER_NAME` in workflows, default `tianlu-k8s`), Container Registry (slug matches image prefix, e.g. `registry.digitalocean.com/<slug>/…`).
2. **GitHub Actions → Setup cluster**: run `install-ingress`, then `docr-pull-secret` (or `full`). Point DNS A records at the Ingress external IP.
3. **Secrets (CI / cluster)** — see **“GitHub secrets: which repo needs what”** above.
   - **kubernetes-devops (repo):** `DIGITALOCEAN_ACCESS_TOKEN`, `GH_PAT_DEVOPS_TOKEN` (write, for manifest commits), `DOCR_REGISTRY_NAME` (for `doctl registry kubernetes-manifest` in setup).
   - **GitHub Environments** `staging` / `prod` **on this repo** — **`MONGODB_URI`**, **`CLERK_SECRET_KEY`**, optional **`SENTRY_DSN`**. **`deploy-production.yml`** / **`deploy-staging.yml`** run **`scripts/ensure-k8s-secrets.sh`** so every deploy syncs **`backend-secrets`** and **`frontend-secrets`** in the cluster — no plaintext secrets in git.
   - **Templates in repo:** `overlays/{staging,prod}/*-secrets.example.yaml` are **committed** (placeholders only). New developers use them as the shape of the Secret; **filled** files should be named `*-secrets.local.yaml` (see `.gitignore`) and **never committed**. Prefer **GitHub Environment secrets** + pipeline; use local apply only for emergencies.
   - **App repos (tianluai_api / tianluai-web):** configure **`DIGITALOCEAN_ACCESS_TOKEN`**, **`DOCR_REGISTRY`**, **`GH_PAT_DEVOPS_TOKEN`** **in each app repo** (repository or Environment secrets + `environment:` on jobs). **tianluai-web** also needs **`NEXT_PUBLIC_*`**, Sentry build args, etc., at **Docker build** time.
4. **Sentry (Next.js):** `NEXT_PUBLIC_SENTRY_DSN` and optional `SENTRY_ORG`, `SENTRY_PROJECT`, `SENTRY_AUTH_TOKEN` are **build-time** in tianluai-web (Docker `ARG` / CI `build-args`), not injected by kubernetes-devops at deploy — the client bundle is baked when the image is built.
5. **Frontend:** `NEXT_PUBLIC_*` is baked at image build time in tianluai-web; the web pod’s server-side Clerk key is mounted via **`frontend-secrets`** (same value as the API if you use one Clerk app).
6. **Where cluster runtime secrets live (mental model):** **GitHub Environment secrets** on **kubernetes-devops** → deploy workflows → **`ensure-k8s-secrets.sh`** → Kubernetes **`Secret`** objects. Kustomize manifests **do not** embed secret values.

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
