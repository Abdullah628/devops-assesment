# DevOps Assessment — Build Plan, Guide & Architecture

> Your learning-oriented roadmap for the LogicMatrix DevOps assessment.
> Read top-to-bottom once, then use it as a checklist while you build.

---

## 1. What we are building & why

The assessment asks for a **production-style platform**: two apps → Docker → Docker Compose →
CI/CD → Kubernetes → private database → Terraform → documentation. The graders care far more about
**design, automation, security, troubleshooting, and explanation** than about whether the app is
fancy. So every artifact here is small, correct, and *explained*.

**Confirmed decisions:**

| Area        | Choice                                                                 |
|-------------|------------------------------------------------------------------------|
| Cloud       | **AWS EKS** (ECR, RDS PostgreSQL in private subnets, private DNS, CloudWatch). *(Switched from Azure AKS on 2026-07-03 — the candidate has real EKS access.)* |
| App stack   | **Node.js** backend (Express) + **static HTML/JS** frontend (Nginx)    |
| Cloud spend | **Free by default, real when you opt in.** Iterate locally (Docker Compose + `kind`) at $0; CI validates on an ephemeral kind cluster; real **ECR push** + real **EKS deploy** are opt-in. Terraform provisions real AWS but is `destroy`-ed after each session (EKS+NAT+RDS ≈ $150–250/mo if left running). |
| CI/CD       | **GitHub Actions** (`.github/workflows/deploy.yml`)                     |

**Guiding principles (the "engineering standard" lens):**

1. Every artifact must be explainable — each folder gets a README / doc section.
2. Secrets never touch git — only `*-secret-example.yaml` placeholders are committed.
3. No `latest` image tags — images are tagged with the git SHA.
4. Reproducible locally — a reviewer with no AWS account can still run and grade everything (Docker Compose + kind).
5. Small, honest commits — conventional-commit messages, one logical unit each.

---

## 2. Repository structure

```
devops-assessment/
├── frontend/            # static HTML/JS + Nginx (multi-stage Dockerfile, non-root)
├── backend/             # Express API on :8080 + jest tests
├── docker-compose.yml   # frontend + backend + postgres (local only)
├── .dockerignore  .gitignore  .env.example
├── .github/workflows/deploy.yml   # CI/CD pipeline
├── k8s/                 # Kubernetes manifests (2 replicas, probes, limits, ingress...)
├── terraform/           # custom modules: network(vpc), eks, ecr, database(rds), monitoring(cloudwatch)
├── docs/                # architecture, cicd, database-connectivity, troubleshooting, future-improvements
├── plan.md              # this file
└── README.md            # top-level overview + quickstart
```

---

## 3. Architecture diagrams

### 3.1 Local development (Docker Compose) — what a reviewer runs

```mermaid
flowchart LR
    browser([Browser])

    subgraph net["docker bridge network"]
        frontend["frontend<br/>nginx :8080<br/>static HTML/JS"]
        backend["backend<br/>node :8080<br/>/ · /health · /db-check"]
        postgres[("postgres<br/>no host port bound")]
    end

    browser -- "host :8081" --> frontend
    frontend -- "proxy /api/* → :8080" --> backend
    backend -- ":5432" --> postgres
```

```
  curl localhost:8080         →  Application is running
  curl localhost:8080/health  →  {"status":"ok"}
  postgres has NO published host port  →  mirrors a "private" database
```

### 3.2 CI/CD flow (GitHub Actions)

```mermaid
flowchart TD
    push["git push / PR"] --> build
    tag["git tag v* / push to main"] --> build
    manual["manual run<br/>deploy_to_eks=true"] --> build

    build["<b>build-test-push job</b><br/>1 checkout<br/>2 setup-node 20<br/>3 npm ci (backend)<br/>4 npm test (jest, gate)<br/>5 docker build frontend+backend<br/>6 smoke-test backend image<br/>7 push ghcr.io + ECR<br/>tag = &lt;git-sha&gt; (never latest)"]

    build --> deploykind
    build --> deployeks
    build --> release

    deploykind["<b>deploy-kind job</b> (auto, FREE)<br/>kind create cluster<br/>kind load images<br/>kubectl apply + set image &lt;sha&gt;<br/>rollout status + /health curl"]
    deployeks["<b>deploy-eks job</b> (manual, REAL AWS)<br/>OIDC → assume role<br/>aws eks update-kubeconfig<br/>kubectl apply + set image &lt;sha&gt;<br/>rollout status"]
    release["<b>release job</b> (on v* tag)<br/>gh release create"]
```

```
  Registry:  ghcr.io (always, free)  +  ECR (real when AWS_ROLE_ARN set)
  GitHub config:  secret AWS_ROLE_ARN · vars AWS_REGION, EKS_CLUSTER_NAME
                  (OIDC — no static AWS keys)      (see docs/cicd.md)
```

### 3.3 AWS target architecture (Terraform provisions this; destroy after each session)

```mermaid
flowchart TD
    internet([Internet])
    internet --> alb["ALB Ingress · public<br/>AWS Load Balancer Controller<br/>exposes ONLY frontend"]

    subgraph eks["EKS cluster — VPC · private subnets"]
        frontend["frontend Deployment<br/>2+ replicas<br/>Service: ClusterIP<br/>readiness/liveness probes<br/>cpu/mem limits"]
        backend["backend Deployment<br/>2+ replicas<br/>Service: ClusterIP (internal only)<br/>reads Secret (DB creds via IRSA/CSI)"]
        frontend -- "http://backend:8080" --> backend
    end

    alb -- "ClusterIP" --> frontend

    subgraph dbnet["VPC · private DB subnets"]
        db[("RDS PostgreSQL<br/>publicly_accessible = false")]
    end

    backend -- "private traffic only<br/>(SG: 5432 from node SG only)" --> db
```

```
  Supporting services (custom Terraform modules):
   • ECR            — node group / IRSA gets AmazonEC2ContainerRegistryReadOnly (no passwords)
   • CloudWatch     — EKS control-plane logs + Container Insights
   • Security Group on RDS — allow 5432 inbound from the node/pod SG only; deny all else
   • Private DNS    — Route 53 private hosted zone resolves the RDS endpoint in-VPC
```

---

## 4. Build order (each phase = one commit, always runnable)

| Phase | Task | Deliverables | Checkpoint |
|-------|------|--------------|-----------|
| **A** ✅ | 1 | backend, frontend, Dockerfiles, docker-compose, .dockerignore, .env.example | `docker compose up -d` → both curl commands pass (**done & verified**) |
| **B** ✅ | 2 | `.github/workflows/deploy.yml`, `docs/cicd.md` | Pipeline green: tests + build; mock push/deploy log clearly (**done**) |
| **C** ✅ | 3 | `k8s/*` manifests | `kind` cluster → `kubectl apply` → pods Ready 2/2 (**manifests done; validated offline + auto-applied by CI deploy-kind**) |
| **D** ✅ | 4 | `docs/database-connectivity.md` | Explains private RDS, private subnets, private DNS, security groups, verification (**done**) |
| **E** ✅ | 5 | `terraform/` custom modules + README | `terraform validate` + `fmt -check` pass (**done & verified**) |
| **F** | 6,7 | `docs/architecture.md`, `troubleshooting.md`, `future-improvements.md`, top-level `README.md` | Docs complete |
| **G** | — | `git init`, commits, secret-leak check | `git ls-files` shows no state/env/keys |

**Legend:** ✅ = complete.

---

## 5. Key implementation rules (pinned)

- Backend `/` returns **exactly** `Application is running` (plain text); `/health` returns
  **exactly** `{"status":"ok"}`; listens on **8080**. The graders test these literally with curl.
- Frontend calls the backend only through the relative `/api/*` path → the same static bundle
  works in both Compose and Kubernetes; the proxy target is set by infrastructure (env/ConfigMap).
- Image tags = git SHA (and semver on release), injected at deploy time — **never `latest`**.
- Containers run **non-root** (backend: `node` user; frontend: nginx-unprivileged).
- CI is real & free by default (ghcr.io push + kind rollout); the AWS steps (ECR push, EKS deploy)
  are real commands that activate on `AWS_ROLE_ARN`/opt-in, with an honest `[MOCK]` echo until then.

---

## 6. How we prove it works (all local & free)

| Task | Verification |
|------|--------------|
| 1 | `docker compose up -d` → `curl localhost:8080` = `Application is running`; `/health` = `{"status":"ok"}`; frontend page shows backend status *(verified ✅)* |
| 2 | Push branch → Actions run green; tag → Release; mock steps logged |
| 3 | `kind create cluster` → `kubectl apply` → `kubectl get pods` all Ready 2/2; backend Service is ClusterIP |
| 4 | Doc review + Terraform shows private RDS & security groups; `nslookup` / `aws rds` verification steps documented |
| 5 | `terraform init -backend=false && terraform validate && terraform fmt -check` pass |
| 6–7 | All 15 troubleshooting questions answered; 6+ improvements with the 5 required sub-points |
| Security | `git ls-files` shows no `.tfstate` / `.env` / keys; only `*-secret-example.yaml` present |

---

## 7. Design choices made for you (flag if you disagree)

- **Ingress:** NGINX Ingress in manifests (portable, works on local `kind`); Terraform notes the
  **AWS Load Balancer Controller** (ALB Ingress) as the production alternative on EKS.
- **Database:** **RDS PostgreSQL** with `publicly_accessible = false` in private subnets (cleaner
  than a VM-hosted DB; reachable only from the cluster's security group).
- **Frontend:** static HTML+JS behind Nginx (no React build) to keep CI fast and Dockerfiles clear
  — the assessment grades DevOps, not front-end frameworks. Easy to swap to React later.
