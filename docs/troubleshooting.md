# Troubleshooting

This document has two parts:

1. **Real incident record** — an actual failure hit while wiring the CI deploy to
   Kubernetes, and exactly how it was diagnosed and fixed. Real, verified, and
   reproducible.
2. **Standard troubleshooting Q&A** (Task 6) — the 15 assessment questions,
   answered briefly. *(Added when Task 6 is completed.)*

---

## 1. Incident record — backend rollout fails on first Kubernetes deploy

**Status:** Resolved ✅ · **Environment:** CI `deploy-kind` job (ephemeral kind cluster)
· **Impact:** backend Deployment never reached Ready; pipeline red. Frontend
unaffected.

### Symptom (what we saw)

The `deploy-kind` job failed at the rollout wait with only:

```
Waiting for deployment "backend" rollout to finish: 1 out of 2 new replicas have been updated...
error: timed out waiting for the condition
```

Unhelpful on its own — it says *that* the rollout stalled, not *why*.

### Investigation (how we made it visible)

The first lesson: **a bare "timed out" is not a diagnosis.** We added diagnostics
to the deploy step so that, on rollout failure, it dumps the real state:

```bash
kubectl get pods -o wide
kubectl describe pods
kubectl logs -l app=backend --all-containers --tail=50
kubectl get events --sort-by=.lastTimestamp | tail -30
```

That immediately turned an opaque timeout into concrete evidence — which is how
both root causes below were found.

### Root cause #1 — ImagePullBackOff + a strict rollout policy (deadlock)

The deploy applied the manifests with their **placeholder image tag** `:v1.0.0`
first, then ran `kubectl set image` to the real commit-SHA tag:

```
kubectl apply -f k8s/       # pods want backend:v1.0.0  ← not present in the cluster
kubectl set image ...:<sha> # then switch to the real, loaded image
```

The `:v1.0.0` pods hit **ImagePullBackOff** (that tag was never built/loaded, and
ghcr is private to the cluster). Combined with the Deployment's
`strategy.rollingUpdate.maxUnavailable: 0` ("never drop below 2 healthy pods"),
the rollout **deadlocked**: it started from 0 healthy pods, so it could never
satisfy "keep 2 healthy" and progress. Hence the timeout.

**Fix #1** — inject the real, already-loaded image reference into the manifests
*before* `kubectl apply`, so pods are born with a valid image:

```bash
sed -i "s|image: .*/backend:.*|image: ${REGISTRY}/${OWNER}/backend:${SHA}|"  k8s/backend-deployment.yaml
sed -i "s|image: .*/frontend:.*|image: ${REGISTRY}/${OWNER}/frontend:${SHA}|" k8s/frontend-deployment.yaml
kubectl apply -f k8s/
```

This is also the professional pattern (image-tag injection at deploy time, like
Kustomize) rather than apply-then-mutate. The manifests keep an immutable
placeholder tag in git (never `:latest`); CI pins the real SHA at deploy time.

### Root cause #2 — `runAsNonRoot` with a non-numeric image user

Fix #1 worked (the image was now `already present on machine`), which uncovered a
**second, previously hidden** failure. The added diagnostics showed:

```
Status:  CreateContainerConfigError
Warning  Failed  kubelet  Error: container has runAsNonRoot and image has
         non-numeric user (node), cannot verify user is non-root
```

The backend image sets `USER node` (a *name*) in its Dockerfile, while the pod's
`securityContext` set `runAsNonRoot: true`. Kubernetes must prove the container is
not root **before** starting it, and it can only verify a **numeric UID** — it
cannot resolve the name `node`. So it refused to start the container.

The frontend was fine because its `securityContext` already used a **numeric**
`runAsUser: 101`.

**Fix #2** — give the backend a numeric UID (the `node` user is uid 1000 in
`node:20-alpine`):

```yaml
securityContext:
  runAsNonRoot: true
  runAsUser: 1000      # numeric → Kubernetes can verify non-root
  runAsGroup: 1000
```

### Verification

After both fixes, `deploy-kind` went green:

```
deployment "backend" successfully rolled out
deployment "frontend" successfully rolled out
backend answers /health inside the kind cluster ✓
```

Both backend pods reach `2/2 Ready`, and the in-cluster `/health` check passes.

### Lessons / prevention

- **Make failures observable first.** The fix only became obvious once the job
  printed `describe` / `logs` / `events`. Diagnostics on failure are now permanent
  in the deploy step.
- **Don't deploy a tag that isn't there.** Pin the real, loaded image at deploy
  time instead of applying a placeholder and mutating it.
- **`runAsNonRoot: true` requires a numeric `runAsUser`.** A Dockerfile `USER name`
  is not verifiable by the kubelet.
- **Fixing one bug can reveal the next.** Bug #1 was real and necessary; it simply
  unmasked bug #2. Layered failures are normal.
- **Know your rollout strategy.** `maxUnavailable: 0` is great for zero-downtime
  updates but will stall a rollout that starts from unhealthy pods.

*(These map directly onto Task 6 questions #1 CrashLoopBackOff, #5 pipeline/deploy
failure, and #7 "deployed but not reachable" — see Part 2.)*

---

## 2. Standard troubleshooting Q&A

### 1. Pod is in `CrashLoopBackOff`. What do you check?
`kubectl describe pod <p>` (Events) and `kubectl logs <p> --previous` (why it died
last time). Common causes: app crashes on startup (bad/missing env, ConfigMap or
Secret not mounted), `OOMKilled` (raise memory limits), a failing **liveness**
probe repeatedly killing it, wrong command/entrypoint, or a dependency unavailable
at boot. (We hit an adjacent one — `CreateContainerConfigError` from a bad
securityContext; see the incident above.)

### 2. Deployment is successful, but app is not reachable. What do you check?
Walk the traffic chain: are pods **Ready** (`kubectl get pods`)? Does the Service
have **endpoints** (`kubectl get endpoints <svc>` — empty = label selector mismatch)?
Right Service port/`targetPort`? Is the **Ingress** correct and the ingress
controller running with an address? DNS/LoadBalancer provisioned? Any NetworkPolicy
blocking it? (Our rollout deadlock made pods never Ready — same symptom.)

### 3. Difference between readiness and liveness probe?
- **Readiness** = "can this pod receive traffic *yet*?" Fail → removed from Service
  endpoints (no traffic), **not** restarted.
- **Liveness** = "is this pod still healthy?" Fail → kubelet **restarts** the
  container.
Use readiness for temporary unavailability (warming up, dependency blip), liveness
for a wedged process. Our `/health` backs both and deliberately does **not** touch
the DB, so a DB hiccup doesn't restart pods.

### 4. Docker build works locally but fails in pipeline. Why?
Environment differences: files present locally but **not committed** (so not in the
CI build context), a `.dockerignore` excluding needed files, **architecture** mismatch
(amd64 vs arm64 — we hit this live), stale local cache masking a missing dependency,
missing build args/secrets, registry-auth/network differences, or case-sensitive
paths (Linux runner vs Windows/Mac).

### 5. Pipeline fails during Docker build. What do you check?
The build log's failing step/layer; base-image pull failures (Docker Hub rate limits
or auth), a failing `RUN` (dependency install/network), files missing from the
context, runner disk space, registry credentials, and Dockerfile syntax. Reproduce
locally with the **same** context (`docker build ./service`).

### 6. Certificate renewal failed. What do you check?
With cert-manager/Let's Encrypt: cert-manager pod logs, and
`kubectl describe certificate/order/challenge`. Is the **ACME HTTP-01 challenge
reachable** (ingress path open, DNS points at the LB)? DNS-01 records correct? Hit an
ACME **rate limit**? Wrong/misconfigured Issuer, or clock skew? Check the cert's
expiry and the CertificateRequest status.

### 7. Ingress returns 502 or 504. What do you check?
**502** = backend refused/returned garbage; **504** = backend too slow / no response.
Check: backend pods Ready and Service **endpoints** populated, backend actually
listening on the `targetPort`, readiness probe passing, ingress read/timeout vs a
slow backend, ingress-controller health, and SG/NetworkPolicy between controller and
pods.

### 8. Vendor SFTP connection to port 22 times out. What do you check?
A **timeout** (vs refused) points at network/firewall dropping packets, not the app.
Check: your **security group / NACL egress** allows outbound 22 to the vendor, the
vendor's firewall **allow-lists your egress IP** (the NAT gateway's EIP), a route to
the internet exists (private subnet → NAT), DNS resolves the vendor host, and the
vendor service is actually up. Test with `nc -zv vendor 22` from a pod/node.

### 9. Terraform plan wants to recreate the cluster. What do you check?
Which attribute shows `# forces replacement` in the plan? Did an input change
unintentionally (cluster `name`, subnets/VPC, `role_arn`, AZ order)? A provider major
upgrade re-keying resources? Real drift? Prefer an in-place path (`moved` blocks,
`state mv`); **never** apply an unexplained cluster replacement in prod — it's an
outage + possible data loss. (See `terraform/README.md`.)

### 10. How would you upgrade AKS/EKS safely?
One **minor version at a time** (no skipping): **control plane first**
(`kubernetes_version` bump, in-place), then the **node group** (managed rolling
replacement, `max_unavailable = 1`). First check deprecated APIs (`pluto`/`kubectl`)
and add-on compatibility (CNI, CoreDNS, kube-proxy). Roll **dev → staging → prod**.
2+ replicas + a PodDisruptionBudget keep it zero-downtime.

### 11. Frontend loads, but backend API calls fail. What do you check?
Browser devtools **Network** tab (status code, CORS, the actual URL called). Then the
frontend's proxy config (our nginx maps `/api/*` → the `backend` Service), whether the
backend is reachable in-cluster
(`kubectl exec deploy/frontend -- wget -qO- backend:8080/health`), backend pods
Ready + endpoints, the `BACKEND_URL` value, and any NetworkPolicy between frontend and
backend.

### 12. Backend pod is running, but database connection times out. What do you check?
A timeout = network, not auth. Check: the RDS **security group** allows 5432 from the
node SG, the `DB_HOST`/`DB_PORT` in the ConfigMap, RDS is in the same VPC and
`available` (not rebooting), private DNS resolves the endpoint, and the connection
pool/`max_connections` isn't exhausted. Our `/db-check` endpoint tests this
end-to-end. (Auth failures look different — they return an error, not a hang.)

### 13. Private DNS is not resolving database hostname. What do you check?
VPC `enableDnsSupport` **and** `enableDnsHostnames` = true; the Route 53 **private
hosted zone is associated with the VPC**; the record actually exists; you're resolving
**from inside the VPC** (a pod/node), not your laptop; the DHCP option set uses
AmazonProvidedDNS; and the hostname is spelled right. Test: `kubectl exec deploy/backend
-- nslookup <db-host>`.

### 14. How would you rotate database credentials safely?
Rotate at the **source** (AWS Secrets Manager) — our RDS uses
`manage_master_user_password`, which supports **automatic rotation**. Secrets Manager
creates a new version; the app reads the latest via the Secrets Store CSI driver /
External Secrets Operator; a rolling restart (or a reconnect) picks it up. For
zero-downtime, use a grace period / dual credentials. Code never changes and nothing
is hardcoded.

### 15. Secrets were accidentally committed to GitHub. What do you do?
Treat it as **compromised immediately** — deletion is not enough (it's in history, and
may be cloned/cached/indexed):
1. **Rotate/revoke** the secret at its source right now (new key/password).
2. **Purge history** (`git filter-repo` or BFG) and force-push.
3. **Invalidate** any sessions/tokens it protected; audit logs for misuse.
4. **Prevent recurrence**: pre-commit secret scanning (gitleaks), branch protection,
   GitHub secret scanning, and keep secrets in Secrets Manager — never in git (this
   repo commits only `*-secret-example` placeholders; see `.gitignore`).
