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

## 2. Standard troubleshooting Q&A (Task 6)

*To be completed in Task 6 — the 15 assessment questions, answered briefly, each
cross-referencing the incident above where relevant.*
