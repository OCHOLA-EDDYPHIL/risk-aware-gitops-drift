# Evaluation Plan

## Test Objective

Evaluate whether RADAR adds security context and explainability beyond raw Argo CD OutOfSync reporting.

## Test Environment

- Local Kubernetes cluster.
- Argo CD managing synthetic demo applications.
- RADAR CLI running from a developer workstation or CI-safe test environment.
- No real production workloads or secrets.

## Drift Scenarios

| Scenario | Expected Severity | Detection Status |
| -------- | ----------------- | ---------------- |
| RBAC escalation | CRITICAL | Policy fixture exists; live MVP scenario pending. |
| NetworkPolicy removal | HIGH | Policy fixture exists; live MVP scenario pending. |
| Privileged container | CRITICAL | Policy fixture exists; live MVP scenario pending. |
| hostPath addition | HIGH | Policy fixture exists; live MVP scenario pending. |
| Service exposure | HIGH | Policy fixture exists; live MVP scenario pending. |
| Unsafe image tag | MEDIUM | Policy fixture exists; live MVP scenario pending. |
| Metadata-only change | LOW | Policy fixture exists; live MVP scenario pending. |

## Metrics

- Expected severity versus observed severity.
- False positives.
- False negatives.
- Time-to-detect placeholder.
- Explanation quality.
- Comparison against raw Argo CD OutOfSync reporting.

## Evidence

Collect sanitized CLI output, JSON result logs, policy test logs, and result tables. Do not include tokens, kubeconfigs, or real cluster URLs.
