# Future Improvement Proposal

The current platform is a correct, production-*style* foundation. These are the
improvements that would take it to genuinely production-*grade*, each with **what**,
**why**, **how it helps**, **how to implement**, and **what risk it reduces**.

They're ordered roughly by impact-per-effort.

---

## 1. Image vulnerability scanning (shift-left security)

- **What:** Scan every image for known CVEs in CI and block on criticals.
- **Why:** Base images and dependencies accumulate vulnerabilities; shipping them is
  a common breach vector.
- **How it helps:** Catches vulnerable images *before* they reach the cluster, and
  gives the team a continuous inventory of exposure.
- **How to implement:** Add a **Trivy** (or Grype) scan step to the CI pipeline after
  build; fail on `HIGH`/`CRITICAL`. ECR already has `scan_on_push = true` as a second
  layer. Add a scheduled re-scan for images already deployed.
- **Risk reduced:** Deploying known-exploitable code; supply-chain compromise.

## 2. Monitoring, metrics & alerting

- **What:** Cluster + app observability with dashboards and alerts.
- **Why:** Today we can `kubectl logs`, but there's no proactive signal — you learn
  about outages from users.
- **How it helps:** See CPU/memory/latency/error trends; get paged *before* customers
  notice; faster incident diagnosis.
- **How to implement:** **Prometheus + Grafana** (via kube-prometheus-stack) for
  metrics/dashboards, **CloudWatch Container Insights** + alarms for infra, and
  Alertmanager → Slack/PagerDuty. Add the four golden signals (latency, traffic,
  errors, saturation).
- **Risk reduced:** Silent failures, slow MTTR, flying blind during incidents.

## 3. Kubernetes autoscaling (HPA + node autoscaling)

- **What:** Scale pods on demand, and nodes to fit them.
- **Why:** Replica count and node count are currently fixed — a traffic spike
  overwhelms it; quiet periods waste money.
- **How it helps:** Handles spikes automatically and shrinks when idle.
- **How to implement:** **HorizontalPodAutoscaler** on backend/frontend (target CPU or
  custom/RPS metrics), plus **Cluster Autoscaler** or **Karpenter** to add/remove
  nodes. Requires resource requests (already set).
- **Risk reduced:** Outages under load; over-provisioning cost.

## 4. GitOps with Argo CD

- **What:** The cluster's desired state lives in git; Argo CD continuously reconciles.
- **Why:** We currently `kubectl apply` from CI (push model) — no single source of
  truth, drift is invisible.
- **How it helps:** Git becomes the audit log; rollbacks are a git revert; drift is
  auto-corrected; deploys are declarative and reviewable.
- **How to implement:** Install **Argo CD**, point Applications at the `k8s/` manifests
  (ideally Kustomize/Helm per environment); CI's job becomes "build + push image +
  bump tag in git," Argo does the deploy.
- **Risk reduced:** Configuration drift, unauditable manual changes, risky rollbacks.

## 5. Progressive delivery (blue/green or canary)

- **What:** Shift traffic to a new version gradually, with automatic rollback on
  errors.
- **Why:** A rolling update still exposes *all* users to a bad release at once.
- **How it helps:** A bad deploy hits 5% of traffic, is detected by metrics, and rolls
  back automatically — most users never see it.
- **How to implement:** **Argo Rollouts** or **Flagger** with canary steps gated on
  Prometheus metrics (error rate, latency).
- **Risk reduced:** Blast radius of a bad release; deploy anxiety.

## 6. Network policies (zero-trust inside the cluster)

- **What:** Default-deny pod-to-pod traffic; explicitly allow only required flows.
- **Why:** By default any pod can talk to any pod — a compromised frontend could reach
  the database directly.
- **How it helps:** Contains lateral movement; enforces "only backend → DB, only
  ingress → frontend."
- **How to implement:** **NetworkPolicy** resources (with a CNI that enforces them,
  e.g. Calico or the VPC CNI + network policy) — default deny, then allow
  frontend→backend and backend→DB only.
- **Risk reduced:** Lateral movement after a single-pod compromise.

## 7. WAF + private cluster + TLS everywhere

- **What:** A Web Application Firewall at the edge, a private EKS API endpoint, and
  HTTPS end-to-end.
- **Why:** The app is exposed over the internet; the API server is publicly reachable;
  traffic isn't guaranteed encrypted.
- **How it helps:** Blocks common attacks (SQLi/XSS, bad bots), rate-limits abuse,
  shrinks the attack surface, and protects data in transit.
- **How to implement:** **AWS WAF** on the ALB, set `endpoint_public_access = false`
  (or restrict to office CIDRs) in the eks module, and **cert-manager + Let's Encrypt**
  (or ACM) for automatic TLS on the Ingress.
- **Risk reduced:** Web attacks, exposed control plane, plaintext interception.

## 8. Backup & disaster recovery

- **What:** Automated backups of the database and cluster state, with a tested restore.
- **Why:** `db_backup_retention_days = 0` (free tier) means **no backups** right now;
  a failure loses data.
- **How it helps:** Recover from data loss, corruption, or region failure within a
  defined RPO/RTO.
- **How to implement:** Set RDS `backup_retention_period` (7–30 days) + snapshots +
  optional cross-region copy; **Velero** for cluster resources/PVs; **document and
  test** the restore runbook.
- **Risk reduced:** Permanent data loss; failed/again-untested recovery.

---

## Already in place (foundations these build on)

Worth noting the platform already does several of these well, so the above are
*next steps*, not gaps in the basics:

- **Secret management** — RDS password in AWS Secrets Manager (auto-rotatable), no
  secrets in git, CI auth via OIDC (no static keys).
- **Terraform remote backend** — S3 + DynamoDB state locking, per-environment state.
- **Cluster upgrade strategy** & **dev/staging/prod separation** — documented and
  implemented (`terraform/README.md`, `docs/environments.md`).
- **Production approval gates** — the CI `deploy-eks` job supports a GitHub Environment
  with required reviewers.
- **Non-root, hardened pods**, immutable image tags, private database.

## Suggested priority order

1. Monitoring/alerting (you're blind without it)
2. Image scanning (cheap, high security value)
3. Autoscaling (handles real load)
4. Backup/DR (turn backups on for prod)
5. Network policies + WAF (defense in depth)
6. GitOps + progressive delivery (delivery maturity)
