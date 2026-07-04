# DevOps Assessment — Production-Style Kubernetes Platform on AWS

A small but production-shaped platform: two containerised apps → Docker Compose →
CI/CD → Kubernetes (EKS) → private database → Terraform → docs. Built on **AWS**
(EKS, ECR, RDS, CloudWatch, VPC).

The emphasis is on **design, automation, security, and explanation** — every
artifact is small, correct, and documented.

---

## What's here (task by task)

| Task | Deliverable | Where |
|------|-------------|-------|
| 1 — Apps, Docker, Compose | Backend API + frontend, Dockerfiles, `docker-compose.yml` | [`backend/`](backend/), [`frontend/`](frontend/), [`docker-compose.yml`](docker-compose.yml) |
| 2 — CI/CD | GitHub Actions: test → build → push (ghcr + ECR) → release → deploy | [`.github/workflows/deploy.yml`](.github/workflows/deploy.yml), [`docs/cicd.md`](docs/cicd.md) |
| 3 — Kubernetes | Deployments, Services, Ingress, ConfigMap, Secret (2 replicas, probes, limits) | [`k8s/`](k8s/) |
| 4 — Private database | EKS → RDS private connectivity design + verification | [`docs/database-connectivity.md`](docs/database-connectivity.md) |
| 5 — Terraform | Custom modules: VPC, EKS, ECR, RDS, CloudWatch; remote state | [`terraform/`](terraform/) |
| 6 — Troubleshooting | Real incident record + 15 answered questions | [`docs/troubleshooting.md`](docs/troubleshooting.md) |
| 7 — Future improvements | 8 improvements with what/why/how/risk | [`docs/future-improvements.md`](docs/future-improvements.md) |
| Bonus — Multi-environment | dev/staging/prod runbook (Terraform workspaces) | [`docs/environments.md`](docs/environments.md) |

## Architecture

```
Internet
   │
   ▼  (Ingress / ALB — frontend only)
┌──────────────── EKS cluster (private subnets) ─────────────────┐
│  frontend Deployment (Nginx)  ──/api/*──►  backend Deployment  │
│  2 replicas, probes, limits              2 replicas, ClusterIP  │
│                                          (internal only)        │
└──────────────────────────────────────────────┬────────────────┘
                                                │ private, SG-restricted
                                                ▼
                                   RDS PostgreSQL (publicly_accessible=false)
                                   password in AWS Secrets Manager
```

## Quickstart (local, no cloud needed)

```bash
docker compose up -d --build

curl http://localhost:8080          # -> Application is running
curl http://localhost:8080/health   # -> {"status":"ok"}
# open http://localhost:8081        # frontend page (proxies /api to backend)

docker compose down -v
```

Backend tests: `cd backend && npm ci && npm test`.

## Deploy to AWS

See [`docs/environments.md`](docs/environments.md) for the full end-to-end runbook
(dev + staging via Terraform workspaces). In short:

```bash
cd terraform
terraform init -backend-config=backend.hcl
terraform workspace new dev
terraform apply -var-file=dev.tfvars
aws eks update-kubeconfig --name devops-assessment-dev --region eu-north-1
kubectl apply -f ../k8s/
# ... then terraform destroy when done
```

## Tech stack

- **Apps:** Node.js/Express backend (`:8080`), static HTML/JS behind Nginx frontend
- **Containers:** multi-stage Dockerfiles, non-root, healthchecks
- **CI/CD:** GitHub Actions → ghcr.io + Amazon ECR, real `kind` deploy + opt-in EKS
- **Orchestration:** Kubernetes / AWS EKS
- **IaC:** Terraform (custom modules only), S3 + DynamoDB remote state
- **Cloud:** AWS — VPC, EKS, ECR, RDS PostgreSQL, CloudWatch, Secrets Manager

## Security & secrets

No secrets are committed. The RDS password is generated and rotated by **AWS
Secrets Manager**; CI authenticates to AWS via **OIDC** (no static keys); only
`*-secret-example` placeholders live in git. See [`.gitignore`](.gitignore),
[`docs/cicd.md`](docs/cicd.md), and [`docs/database-connectivity.md`](docs/database-connectivity.md).

## Cost note

`terraform apply` creates billable AWS infrastructure (EKS + NAT + RDS ≈
$150–250/mo if left running). The stack is designed to **apply, demo, and
`terraform destroy`** in the same session. Everything also runs **free locally**
via Docker Compose and `kind`.

## Repository layout

```
backend/            frontend/            docker-compose.yml   .dockerignore
.github/workflows/  k8s/                 terraform/           docs/
README.md
```
