# Multi-Environment Runbook (dev & staging on AWS)

End-to-end, copy-paste steps to bring up **dev** and **staging** as fully separate
environments on AWS, deploy the app to each, and tear them down.

**Strategy:** *same Terraform code, different variables, isolated state.*
- Config differences live in `dev.tfvars` / `staging.tfvars` (region, sizes, CIDR).
- State is isolated with **Terraform workspaces** (`dev`, `staging`) on a shared S3
  backend — each workspace's state is stored separately, so applying to dev can
  never affect staging.

| | dev | staging |
|---|---|---|
| Nodes | 1 × `m7i-flex.large` | 2 × `m7i-flex.large` |
| VPC CIDR | `10.0.0.0/16` | `10.1.0.0/16` |
| Cluster name | `devops-assessment-dev` | `devops-assessment-staging` |
| State (workspace) | `env:/dev/…` | `env:/staging/…` |

> 💸 Everything here is billable. Free-tier-eligible sizes are used, but EKS + NAT
> + RDS still draw credits. **`terraform destroy` each environment when done.**

---

## 0. One-time setup (run once)

All commands run in **AWS CloudShell** (already authenticated), region `eu-north-1`.

```bash
# a) install terraform + kubectl into your home dir (persists across CloudShell resets)
mkdir -p ~/bin
curl -sSLo /tmp/tf.zip https://releases.hashicorp.com/terraform/1.9.5/terraform_1.9.5_linux_amd64.zip
unzip -o /tmp/tf.zip -d ~/bin
curl -sSLo ~/bin/kubectl https://dl.k8s.io/release/v1.30.0/bin/linux/amd64/kubectl
chmod +x ~/bin/kubectl
echo 'export PATH="$HOME/bin:$PATH"' >> ~/.bashrc
export PATH="$HOME/bin:$PATH"

# b) get the code
git clone https://github.com/Abdullah628/devops-assesment.git
cd devops-assesment/terraform

# c) bootstrap the remote state bucket + lock table (names must be globally unique)
BUCKET="devops-assessment-tfstate-$RANDOM"
aws s3api create-bucket --bucket "$BUCKET" --region eu-north-1 \
  --create-bucket-configuration LocationConstraint=eu-north-1
aws s3api put-bucket-versioning --bucket "$BUCKET" \
  --versioning-configuration Status=Enabled
aws dynamodb create-table --table-name tf-locks --region eu-north-1 \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH --billing-mode PAY_PER_REQUEST
echo "STATE BUCKET = $BUCKET"     # note this name

# d) create backend.hcl from the example, using that bucket
cp backend.hcl.example backend.hcl
sed -i "s/my-tf-state-bucket-CHANGE_ME/$BUCKET/; s/my-tf-locks-CHANGE_ME/tf-locks/" backend.hcl

# e) initialise the backend
terraform init -backend-config=backend.hcl
```

---

## 1. Deploy DEV

```bash
# create + switch to the dev workspace (isolated state)
terraform workspace new dev        # (later: terraform workspace select dev)

# review, then build
terraform plan  -var-file=dev.tfvars
terraform apply -var-file=dev.tfvars      # type yes  (~15-20 min)
```

Then deploy the app to the dev cluster:

```bash
aws eks update-kubeconfig --name devops-assessment-dev --region eu-north-1
kubectl apply -f ../k8s/

# point the deployments at your real images (packages must be PUBLIC on ghcr;
# use a real commit-SHA tag, e.g. the latest from `git -C .. log --oneline -1`)
TAG=$(git -C .. rev-parse --short HEAD)
kubectl set image deployment/backend  backend=ghcr.io/abdullah628/backend:$TAG
kubectl set image deployment/frontend frontend=ghcr.io/abdullah628/frontend:$TAG

kubectl get pods -o wide          # show it to the grader: pods Running
kubectl get nodes                 # 1 node
```

**Prove it lives on dev:**
```bash
kubectl port-forward deploy/backend 8080:8080 >/dev/null 2>&1 &
sleep 3; curl http://localhost:8080/health; curl http://localhost:8080/; kill %1
```

---

## 2. Deploy STAGING (separate everything)

```bash
# NEW workspace = NEW isolated state. dev is untouched.
terraform workspace new staging

terraform plan  -var-file=staging.tfvars
terraform apply -var-file=staging.tfvars   # type yes  (~15-20 min)
```

Deploy the app to the staging cluster:

```bash
aws eks update-kubeconfig --name devops-assessment-staging --region eu-north-1
kubectl apply -f ../k8s/
TAG=$(git -C .. rev-parse --short HEAD)
kubectl set image deployment/backend  backend=ghcr.io/abdullah628/backend:$TAG
kubectl set image deployment/frontend frontend=ghcr.io/abdullah628/frontend:$TAG

kubectl get pods -o wide
kubectl get nodes                 # 2 nodes (bigger than dev)
```

---

## 3. Switching between environments (for the demo)

```bash
terraform workspace list          # shows: default, dev, staging (* = current)
terraform workspace select dev    # now targeting dev
terraform workspace select staging

# kubectl follows whichever cluster you last pointed it at:
aws eks update-kubeconfig --name devops-assessment-dev     --region eu-north-1
aws eks update-kubeconfig --name devops-assessment-staging --region eu-north-1
```

Show the grader they are genuinely separate:
```bash
aws eks list-clusters --region eu-north-1     # both clusters listed
aws ec2 describe-vpcs --region eu-north-1 \
  --query 'Vpcs[].{cidr:CidrBlock,name:Tags[?Key==`Name`]|[0].Value}' --output table
# -> one VPC on 10.0.0.0/16 (dev), one on 10.1.0.0/16 (staging)
```

---

## 4. Tear down (do this after the demo!)

Destroy **each** environment from its own workspace:

```bash
terraform workspace select staging
terraform destroy -var-file=staging.tfvars   # type yes

terraform workspace select dev
terraform destroy -var-file=dev.tfvars        # type yes
```

Verify nothing is left: `aws eks list-clusters --region eu-north-1` → empty.

---

## Notes for the grader

- **One codebase, three environments.** Adding **prod** later is just a
  `prod.tfvars` (bigger nodes, `db_multi_az=true`, `db_backup_retention_days=7`)
  and `terraform workspace new prod` — no code changes.
- **Isolated state** via workspaces means an accidental `apply` in dev can never
  corrupt staging. Production-grade setups often go further and use a **separate
  AWS account per environment** for the strongest isolation.
- **No secrets in any of this** — the RDS password is generated and rotated by
  AWS Secrets Manager (`manage_master_user_password`), never in Terraform, tfvars,
  or state.
