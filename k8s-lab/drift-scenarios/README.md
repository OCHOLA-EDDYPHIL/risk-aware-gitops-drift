# Guarded Controlled-Drift Scenarios

`scripts/run-scenario.sh` accepts exactly one scenario and one positive repetition number. It refuses any context other than `radar-lab`, refuses a dirty baseline or mutable Application revision, changes only the live synthetic namespace, and never edits Git. The synchronized revision and latest successful Argo CD sync operation must equal the immutable target commit before drift is injected, preventing source reconciliation from clearing the mutation during observation. An optional `--environment-file` supplies a pre-captured provenance manifest whose source commit must match that revision.

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
  --scenario networkpolicy-removal \
  --repetition 1
```

The runner records the declared mutation and timestamps, forces an Argo CD refresh, verifies `OutOfSync`, and captures one Application and managed-resource snapshot through a localhost-only port-forward. RADAR classifies that exact captured bundle before the runner checks the expected rule. The runner then recreates only `radar-demo` through an explicit Argo CD synchronization and records verified `Synced`, `Healthy`, and declared-field baseline state. Results are stored as `k8s-lab/evidence/<scenario>/run-NNN/` and are ignored by Git by default.

These runs observe configuration drift only. They do not execute attacks, expose services outside Minikube, or use real credentials.
