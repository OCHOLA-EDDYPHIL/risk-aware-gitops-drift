# Guarded Controlled-Drift Scenarios

`scripts/run-scenario.sh` requires a research collection identifier, one scenario, one positive repetition number and a checksummed environment manifest. It refuses any context not bound to the `radar-lab` Minikube profile, any dirty worktree, mutable or mismatched Application revision, and any external scanner binary. The scanner and policy are built from the immutable synchronized commit before drift is injected.

| Scenario argument | Live mutation | Expected rule | Severity |
| --- | --- | --- | --- |
| `rbac-wildcard` | Replace the demo Role rules with wildcard access | `RADAR-RBAC-WILDCARD` | CRITICAL |
| `networkpolicy-removal` | Delete the default-deny NetworkPolicy | `RADAR-NETPOL-REMOVED` | HIGH |
| `privileged-container` | Set the demo container to privileged | `RADAR-WORKLOAD-PRIVILEGED` | CRITICAL |
| `hostpath-addition` | Replace the scratch `emptyDir` with a hostPath | `RADAR-VOLUME-HOSTPATH` | HIGH |
| `service-exposure` | Change the Service from ClusterIP to NodePort | `RADAR-SERVICE-EXPOSURE` | HIGH |
| `unsafe-image-tag` | Change the versioned image to `nginx:latest` | `RADAR-IMAGE-LATEST` | MEDIUM |
| `secret-reference` | Change the dummy Secret reference from v1 to v2 | `RADAR-SECRET-REFERENCE` | MEDIUM |
| `metadata-only` | Change one existing non-security Deployment label | `RADAR-METADATA-ONLY` | LOW |

Example:

```sh
k8s-lab/scripts/run-scenario.sh \
  --context radar-lab \
  --collection-id runner-integrity-v1 \
  --scenario networkpolicy-removal \
  --repetition 1 \
  --environment-file k8s-lab/evidence/runner-integrity-v1/environment.json
```

The runner records the declared mutation and timestamps, forces an Argo CD refresh, verifies `OutOfSync`, and accepts managed-resource evidence only when equal-resource-version Application snapshots bracket its capture. A dynamically allocated localhost port must belong to the spawned forwarding process. RADAR classifies the exact captured bundle before the expected rule is checked. Reset uses the original immutable revision and records the successful operation, `Synced`, `Healthy`, and declared-field baseline state. Raw results are stored under `k8s-lab/evidence/<collection-id>/` and are ignored by Git by default.

These runs observe configuration drift only. They do not execute attacks, expose services outside Minikube, or use real credentials.
