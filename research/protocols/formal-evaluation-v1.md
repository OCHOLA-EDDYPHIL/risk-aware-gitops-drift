# RADAR Formal Evaluation Protocol v1

## Purpose and freeze boundary

This protocol evaluates the frozen RADAR prototype in one isolated Minikube and Argo CD environment. It contains seven declared security scenarios and one benign metadata control, with ten repetitions per scenario. The machine-readable companion manifest fixes all 80 run identifiers and expected decisions before execution.

The freeze consists of the immutable source commit used by every run, the SHA-256 values of this protocol manifest, the Rego policy, the risk-matrix document and the captured environment manifest. A change to code, policy, risk matrix, protocol or a material environment component ends the current corpus and requires a versioned replacement protocol. Evidence from different freezes must not be combined.

## Declared scenarios and ground truth

| Scenario | Ground truth | Expected rule | Expected severity | Expected score |
| --- | --- | --- | --- | ---: |
| RBAC wildcard | Security | `RADAR-RBAC-WILDCARD` | Critical | 100 |
| NetworkPolicy removal | Security | `RADAR-NETPOL-REMOVED` | High | 64 |
| Privileged container | Security | `RADAR-WORKLOAD-PRIVILEGED` | Critical | 100 |
| hostPath addition | Security | `RADAR-VOLUME-HOSTPATH` | High | 60 |
| Service exposure | Security | `RADAR-SERVICE-EXPOSURE` | High | 64 |
| Unsafe image tag | Security | `RADAR-IMAGE-LATEST` | Medium | 36 |
| Secret-reference change | Security | `RADAR-SECRET-REFERENCE` | Medium | 32 |
| Metadata-only change | Benign control | `RADAR-METADATA-ONLY` | Low | 4 |

The declared JSON Pointer for each expected finding is fixed in the companion manifest. No expected severity, score, path or rule may be changed after the first run.

## Execution procedure

1. Use only the profile and Kubernetes context named `radar-lab` in the isolated execution environment.
2. Confirm the worktree is clean and the Argo CD target, synchronized and latest successful operation revisions equal the immutable source commit.
3. Capture the pinned environment and verify the declared baseline.
4. For each manifest run ID, apply exactly one declared live mutation without changing Git.
5. Wait for Argo CD `OutOfSync`, capture one stable bracketed Application and managed-resource bundle, run the frozen RADAR binary and policy, and preserve the result.
6. Reset through an explicit Argo CD operation to the same immutable revision and verify `Synced`, `Healthy` and every declared baseline field before continuing.
7. Sanitize, validate, package, checksum and index every terminal run, including failures.

Runs execute sequentially in manifest order. Existing terminal run IDs are immutable and must never be overwritten. An interrupted collection may resume only missing run IDs when the source, protocol and environment remain unchanged. An unverified reset stops execution immediately.

## Evidence and run accounting

Schema version 4 binds each run to its declared run ID, protocol hash, source commit, scanner hash, policy hash, risk-matrix hash, environment hash, stable captured input, expected decision and reset operation. Each of the 80 declarations must be recorded as completed, failed, interrupted or excluded with a reason. Missing runs remain visible and are not silently removed from denominators.

## Metrics

- Detection accuracy is the number of declared security runs containing their expected security rule divided by all 70 declared security runs.
- A false negative is a declared security run without its expected security classification.
- A false positive is a metadata-control run classified Medium or higher. Incomplete controls are reported separately.
- Exact severity accuracy is the number of completed runs whose observed expected finding has the declared severity divided by all completed runs.
- Time to detect is `radarCompletedAt - mutationAt` for completed runs with valid timestamps.
- Processing latency is `radarCompletedAt - observedAt` for completed runs with valid timestamps.
- Explanation completeness requires the expected finding to contain the affected resource, atomic change, severity, reason and recommendation.
- Median and p95 use the valid completed timing population. P95 uses the nearest-rank method.
- The confusion matrix uses evaluable classified runs; incomplete runs are reported outside the matrix.

All denominators, missing runs, failures and exclusions must appear in the generated run-accounting and metric outputs. Results are limited to the synthetic single-cluster testbed and must not be generalized to production effectiveness.
