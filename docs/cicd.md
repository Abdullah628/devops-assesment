# CI/CD Pipeline

The pipeline is defined in [`.github/workflows/deploy.yml`](../.github/workflows/deploy.yml)
using **GitHub Actions**, targeting **AWS** (ECR + EKS). It runs **real end-to-end
at zero cost by default**: every push builds, tests, pushes real images to
**ghcr.io**, and performs a **real Kubernetes rollout** on a `kind` cluster inside
the runner — no AWS account needed. The **real AWS** path (ECR push + EKS deploy)
activates when you add an `AWS_ROLE_ARN` secret, and the EKS rollout is a manual,
opt-in trigger so a billed cluster is never touched automatically.

## Pipeline at a glance

```
 push / PR ─▶ build-test-push ─┬─▶ release      (only on v* tags)
                               └─▶ deploy-kind   (real kind cluster + rollout, FREE)
                               ↑ quality gate: tests must pass

 manual run (deploy_to_eks=true) ─▶ deploy-eks   (real EKS rollout, opt-in, billed)
```

| # | Job | Trigger | What it does |
|---|-----|---------|--------------|
| 1 | **build-test-push** | every push & PR | checkout → Node 20 → `npm ci` → `npm test` (gate) → build both images → smoke-test the backend image (`/health` must answer) → **push both images to ghcr.io** (skipped on PRs) |
| 2 | **release** | push of a `v*` tag | create a GitHub Release listing the pushed image tags |
| 3 | **deploy-kind** | push to `main` / tags | **default, free** path: create a **real kind cluster**, load the images, `kubectl apply` + `set image` to the SHA tag, wait for rollout, then curl `/health` **inside the cluster** |
| 4 | **deploy-eks** | manual (`workflow_dispatch`, `deploy_to_eks=true`) | **opt-in, real cloud**: OIDC into AWS, `aws eks update-kubeconfig`, `kubectl apply` + `set image` against the real **EKS** cluster, wait for rollout. Never runs automatically (it's billed). |

### How each Task 2 requirement is met

| Requirement | Where | Real or mock |
|-------------|-------|--------------|
| Checkout code | `actions/checkout@v4` in every job | real |
| Install dependencies | `npm ci` in `build-test-push` | real |
| Run tests | `npm test` (jest) — a hard gate; failure stops the pipeline | real |
| Build frontend image | `docker/build-push-action` on `./frontend` | real |
| Build backend image | `docker/build-push-action` on `./backend` | real |
| Tag both images | `git rev-parse --short HEAD` — **never `latest`** | real |
| Push images to registry | `docker push` to **ghcr.io** with `GITHUB_TOKEN` | **real** |
| Push images to Amazon ECR | OIDC → `aws ecr get-login-password` + `docker push` to `*.dkr.ecr.*.amazonaws.com`, guarded by a `MOCK` flag | **real when `AWS_ROLE_ARN` set**, else `[MOCK]` echo |
| Create a GitHub release / tag | `release` job → `gh release create` on `v*` tags | **real** |
| Deploy to Kubernetes | `deploy-kind` (free) + `deploy-eks` (real EKS, opt-in) → `kubectl apply` / `set image` + rollout check | **real** |

> **ghcr.io vs. ECR.** The assessment names **AWS ECR** as the cloud registry but
> allows mocking the push. The pipeline does both: a **real, free** push to
> **ghcr.io** (proving the build→push→pull→deploy chain genuinely works) *and* a
> **real ECR** push that activates the moment you add an `AWS_ROLE_ARN` secret
> (OIDC federation — no static AWS keys). Until then the ECR step prints its real
> `aws ecr` / `docker push` commands behind a `[MOCK]` label, so nothing is
> silently faked.

## Why image tags are the git SHA, never `latest`

`latest` is a **mutable** pointer: two different builds can both be `latest`, so
you can never prove which commit is actually running in a cluster, and a rollback
target is ambiguous. Tagging with the immutable commit SHA (`a1b2c3d`) gives:

- **Traceability** — every running pod maps to exactly one commit.
- **Safe rollback** — redeploying is just `kubectl set image ...:<old-sha>`.
- **Cache correctness** — a new commit is always a new tag, so nodes never serve
  a stale image that happens to share a tag.

## Two deploy paths: free-by-default, real-cloud-on-demand

Deploying to a real EKS cluster on every push would be slow and would keep a
billed cluster alive constantly. So the pipeline splits the deploy in two:

- **`deploy-kind` (automatic, free).** On every push, `helm/kind-action` boots a
  real single-node Kubernetes cluster inside the runner. Images are loaded with
  `kind load docker-image`, manifests are applied, and the job blocks on a **real
  `kubectl rollout status`** plus a `/health` curl **from inside the cluster**. If
  the rollout doesn't converge, the pipeline fails. This validates the deploy on
  every commit at zero cost.
- **`deploy-eks` (manual, real AWS).** Triggered only via **Run workflow →
  `deploy_to_eks = true`**. It uses GitHub **OIDC** to assume an AWS IAM role (no
  static keys), runs `aws eks update-kubeconfig`, then the **same**
  `kubectl apply` / `set image` / `rollout status` against the real EKS cluster
  provisioned by [`../terraform/`](../terraform/). Because it touches a billed
  cluster it never runs on its own — and you should `terraform destroy` when done.

The two paths run identical `kubectl` — kind proves the manifests work for free;
EKS runs the exact same thing on real infrastructure when you choose to.

### Registry: ghcr.io (free) + ECR (real AWS)

Images always go to **ghcr.io** (free, `GITHUB_TOKEN`, real pullable images at
`ghcr.io/<owner>/backend:<sha>`). The **ECR** push activates automatically once an
`AWS_ROLE_ARN` secret exists; pods on EKS pull from ECR via the node/IRSA IAM role
(`AmazonEC2ContainerRegistryReadOnly`) — no stored registry password.

### Once the k8s/ manifests exist (Task 3)

The `deploy-kind` job prefers `k8s/` if present: `kubectl apply -f k8s/` then pins
images to this build's SHA with `kubectl set image`. Until those manifests land it
does a minimal but genuinely real `kubectl create deployment`, so the rollout still
happens and is verified. `deploy-eks` always applies `k8s/`.

---

## Secret management — how secrets are stored safely

**Nothing secret is ever committed to git.** The repository contains only
non-secret configuration and `*-example` placeholders. Real values live outside
the code, injected at run time.

### Secrets this pipeline uses

The working pipeline needs **zero configured secrets**. It relies only on the
`GITHUB_TOKEN` that Actions injects automatically — used for both the ghcr.io push
and the GitHub Release. Nothing to set up, nothing to leak.

| Secret | Source | Used for |
|--------|--------|----------|
| `GITHUB_TOKEN` | auto-provided by Actions (never stored by you) | ghcr.io push + `gh release create` |

The AWS path (real ECR push + real EKS deploy) adds one **secret** and two
non-secret **variables** under **Repo → Settings → Secrets and variables →
Actions**:

| Name | Kind | Purpose |
|------|------|---------|
| `AWS_ROLE_ARN` | **secret** | IAM role that GitHub OIDC assumes (e.g. `arn:aws:iam::123456789012:role/gha-deploy`) |
| `AWS_REGION` | variable | e.g. `us-east-1` |
| `EKS_CLUSTER_NAME` | variable | the cluster name from `terraform/` (Task 5) |

Note there is **no `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY`** — the pipeline
uses **OIDC federation**: GitHub presents a short-lived token, AWS STS exchanges it
for temporary credentials scoped to `AWS_ROLE_ARN`. No long-lived cloud keys are
ever stored as secrets. This is the current best practice for CI→AWS auth.

In the workflow they are referenced only as `${{ secrets.NAME }}`, mapped into
step-scoped `env:` — so they are masked in logs and never appear in the source.

### Where secrets should live, by platform

The task asks how secrets should be stored across tooling. Principle: **each
secret in exactly one system of record, injected at run time, never in git.**

| Context | Store secrets in | Notes |
|---------|------------------|-------|
| **GitHub Actions** | **GitHub Secrets** (repo/environment-scoped) | Masked in logs; use *Environment* secrets + required reviewers for prod. |
| **Jenkins** | **Jenkins Credentials** (Credentials Binding plugin) | Injected as env vars via `withCredentials`; never `echo`ed. |
| **Azure DevOps** | **Variable Groups** backed by **Azure Key Vault** | Mark variables *secret*; link the group to Key Vault so rotation is central. |
| **Runtime / app secrets (K8s)** | **AWS Secrets Manager** via the **Secrets Store CSI driver** (or **External Secrets Operator**) | Pods mount secrets at runtime via **IRSA**; nothing sensitive in manifests — see [`k8s/backend-secret-example.yaml`](../k8s/backend-secret-example.yaml). |
| **Cloud registry auth** | **IAM role** on the node group / **IRSA** (`AmazonEC2ContainerRegistryReadOnly`) | Preferred over static registry credentials: EKS pulls from ECR with no stored password. |

### Best practices applied here

1. **Least privilege** — the workflow token scopes are `contents`/`packages`/
   `id-token` only, each with a stated reason; nothing broader.
2. **No static cloud keys** — CI authenticates to AWS via **OIDC** (`AWS_ROLE_ARN`),
   and EKS pulls from ECR via the **node/IRSA IAM role** — so neither AWS access
   keys nor a registry password is ever stored as a secret.
3. **Environment scoping + approval gates** — `deploy-eks` is manual/opt-in today;
   for a human approval gate, create a `production` GitHub *Environment* with
   required reviewers and add `environment: production` to the job (a commented
   note in the workflow shows exactly where).
4. **Rotation** — because runtime secrets live in AWS Secrets Manager (not git),
   they can be rotated centrally without touching code. See the secret-rotation
   answer in [`troubleshooting.md`](./troubleshooting.md).
5. **If a secret leaks** — revoke/rotate it immediately at the source, then purge
   history; a committed secret must be treated as compromised even after deletion
   (see the same troubleshooting doc).
