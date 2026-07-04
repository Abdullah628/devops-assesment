# Terraform — AWS EKS Platform

Module-based Terraform that provisions the whole platform on AWS: a custom VPC,
an EKS cluster + managed node group, ECR, a private RDS PostgreSQL database, and
CloudWatch logging. **All modules are custom** — no third-party/registry modules.

> 💸 **Cost warning.** `terraform apply` here creates **billable** infrastructure
> (EKS control plane ≈ \$0.10/hr, NAT gateway ≈ \$0.045/hr, RDS, etc.) — roughly
> **\$150–250/month if left running**. For learning, apply, test, and then
> **`terraform destroy` the same session.** The code is written to be
> `validate`/`plan`-clean without applying.

## Layout

```
terraform/
├── provider.tf              # providers + S3 remote backend (state locking)
├── variables.tf             # env, region, cluster name, node size/count, k8s version, ...
├── main.tf                  # wires the modules together
├── outputs.tf               # cluster name, endpoint, registry URLs, VPC id, ...
├── terraform.tfvars.example # sample variable values
├── backend.hcl.example      # sample remote-backend config
└── modules/                 # custom modules only
    ├── network/             # VPC, 3-tier subnets, IGW, NAT, route tables
    ├── eks/                 # cluster, managed node group, IAM, OIDC (IRSA)
    ├── ecr/                 # backend + frontend image repositories
    ├── database/            # private RDS PostgreSQL, SG, subnet group
    └── monitoring/          # CloudWatch log groups
```

## What it provisions (Task 5 checklist)

| Requirement | Where |
|-------------|-------|
| VPC | `modules/network` |
| Network & subnet design | `modules/network` (public / private-app / private-db) |
| EKS cluster | `modules/eks` |
| Node group | `modules/eks` (managed node group) |
| ECR | `modules/ecr` |
| Monitoring (CloudWatch) | `modules/monitoring` + EKS control-plane logging |
| Private database connectivity | `modules/database` (`publicly_accessible=false`, SG from nodes only) |
| Remote backend & state locking | `provider.tf` (S3 + DynamoDB) |
| Variables (env, region, name, node size/count, k8s version) | `variables.tf` |
| Outputs (cluster name, endpoint, registry, network id) | `outputs.tf` |

## Usage

```bash
# 0. (one-time) create the state bucket + lock table — see below.
cp backend.hcl.example backend.hcl && edit it
cp terraform.tfvars.example terraform.tfvars && edit it

# 1. init with the remote backend
terraform init -backend-config=backend.hcl

# 2. review — this makes NO changes
terraform validate
terraform plan

# 3. apply only when you mean it (billable!)
terraform apply

# 4. connect kubectl (see the kubeconfig_command output)
aws eks update-kubeconfig --name <cluster> --region <region>

# 5. ALWAYS tear down after a learning session
terraform destroy
```

To validate without any AWS credentials or backend:

```bash
terraform init -backend=false
terraform validate
terraform fmt -check -recursive
```

---

## Remote backend & state locking

State lives in **S3** (durable, encrypted, shared) and is locked with a
**DynamoDB** table so two applies can't run at once and corrupt it. These two must
exist **before** `init` (chicken-and-egg: Terraform can't store its own backend in
state it doesn't have yet), so bootstrap them once:

```bash
aws s3api create-bucket --bucket my-tf-state-bucket --region us-east-1
aws s3api put-bucket-versioning --bucket my-tf-state-bucket \
  --versioning-configuration Status=Enabled
aws dynamodb create-table --table-name my-tf-locks \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST
```

Then put those names in `backend.hcl`. **Versioning on** means you can recover a
previous state if something goes wrong.

---

## Operations & maintenance (the required explanations)

### How to safely upgrade EKS

Upgrade **one minor version at a time** (you can't skip versions), control plane
first, then nodes:

1. Bump `kubernetes_version` (e.g. `1.30` → `1.31`), `plan`, `apply`. This upgrades
   the **control plane** only — an in-place, non-destructive change.
2. Upgrade the **node group** to match. Managed node groups do a **rolling
   replacement**: new nodes on the new version join, pods drain off old nodes
   (respecting `max_unavailable = 1`), old nodes terminate — no full outage.
3. Before upgrading, check deprecated APIs (`kubectl` + `kubectl-convert` / the
   `pluto` tool) and confirm your workloads and add-ons (CNI, CoreDNS, kube-proxy)
   support the target version.
4. Do it in **dev → staging → prod** order.

### How to add or resize node pools

- **Resize (bigger nodes):** change `node_instance_type` and `apply`. The managed
  node group rolls in new-sized nodes and drains the old ones.
- **Scale (more/fewer nodes):** change `node_desired_count` / `min` / `max`. (Note:
  the module `ignore_changes` on `desired_size` so the Cluster Autoscaler can move
  it at runtime without Terraform reverting it — set the floor/ceiling here.)
- **Add another pool:** instantiate a second node group (e.g. a `modules/eks`
  variant or an additional `aws_eks_node_group`) for a different instance type,
  taints, or spot capacity. Adding a pool is additive and non-disruptive.

### How to maintain Terraform state

- One **remote state per environment** (separate S3 keys — see below), never
  local.
- **Never** hand-edit state; use `terraform state mv` / `import` / `rm` for
  surgical changes.
- S3 **versioning** enabled for recovery; **DynamoDB lock** prevents concurrent
  writes.
- Keep state small and focused; don't commit `.tfstate` (it can contain secrets —
  it's git-ignored here).

### How to avoid downtime during cluster changes

- Apps run **2+ replicas** with readiness/liveness probes (see `k8s/`), so losing
  one node/pod keeps the service up.
- Node group `max_unavailable = 1` → only one node is replaced at a time.
- Deployments use a rolling update with `maxUnavailable: 0` → new pods must be
  Ready before old ones go.
- Multi-AZ subnets; RDS `multi_az = true` in prod for a standby.
- Add a **PodDisruptionBudget** so voluntary drains never remove too many pods.

### How to separate dev, staging, and production

- Same code, **different variables + different state**:
  ```bash
  terraform init  -backend-config=backend.dev.hcl     # key = .../dev/terraform.tfstate
  terraform apply -var-file=dev.tfvars

  terraform init  -reconfigure -backend-config=backend.prod.hcl  # .../prod/...
  terraform apply -var-file=prod.tfvars
  ```
- The `environment` variable prefixes every resource name and drives safety
  toggles (prod gets `deletion_protection`, a final snapshot, and multi-AZ).
- Prefer **separate AWS accounts** per environment for the strongest blast-radius
  isolation. (Terraform *workspaces* are an alternative, but separate state
  keys/accounts are clearer for prod.)

### How to handle secrets outside Terraform code

- The **DB password is never in Terraform**: `manage_master_user_password = true`
  makes RDS generate and rotate it in **AWS Secrets Manager**. Terraform only
  outputs the secret's ARN, not the value.
- **No secrets in code, tfvars, or state-by-hand.** `*.tfvars` and `*.tfstate` are
  git-ignored.
- Apps read secrets at runtime via **IRSA + Secrets Store CSI / External Secrets**,
  not from Terraform.
- CI authenticates to AWS via **OIDC** (no static keys) — see `docs/cicd.md`.

### What to check if Terraform wants to recreate the cluster

A `plan` showing the cluster/node group will be **destroyed and recreated** (look
for `-/+` / "forces replacement") is a red flag — investigate before applying:

- **Which attribute forces replacement?** `plan` prints `# forces replacement`
  next to it. Common culprits: changing `name`, `subnet_ids`/VPC, cluster
  `role_arn`, or an immutable node-group field.
- **Did an input change unintentionally?** e.g. AZ list reordered, name prefix
  changed, a data source now returns something different.
- **Provider/schema drift** after an `aws` provider major upgrade can re-key
  resources — read the upgrade guide.
- **Prefer an in-place path:** many changes (version, scaling) are in-place. If a
  change is truly immutable but you must keep the resource, use `terraform state
  mv` / `moved` blocks or `-target` carefully, or add a new resource and migrate
  rather than replacing the live cluster.
- **Never** apply an unexplained cluster replacement in prod — it's a full outage
  and data (e.g. RDS) loss risk. Confirm the diff first.

---

## Notes

- After `apply`, install cluster add-ons as needed: the **AWS Load Balancer
  Controller** (for ALB Ingress), **Secrets Store CSI driver**, **Cluster
  Autoscaler / Karpenter**, and **Container Insights** — each via an IRSA role
  bound to the OIDC provider this stack creates.
- The `k8s/` manifests deploy onto the cluster this Terraform builds; CI's
  `deploy-eks` job targets it (see `docs/cicd.md`).
