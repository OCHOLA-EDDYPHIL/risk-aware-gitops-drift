# Evaluation Plan

## Test objective

Evaluate whether RADAR adds correct, reproducible security context and explanations beyond raw Argo CD `OutOfSync` reporting.

## Evidence boundary

Policy fixtures establish deterministic implementation behavior only. Controlled-lab observations begin only after the pinned `radar-lab` environment passes its preflight and a scenario is executed against Argo CD. Formal evaluation results require the separate frozen protocol and repeated-run dataset.

## Controlled environment

- Minikube 1.38.1 with Kubernetes 1.35.6, Docker driver, 2 CPUs, and 3 GiB RAM.
- Dedicated profile and context `radar-lab`; every Kubernetes command names it explicitly.
- Argo CD 3.4.5 managing the synthetic baseline with self-heal disabled.
- RADAR CLI built with Go 1.22 compatibility and OPA 1.17.1.
- Localhost-only Argo CD forwarding and a least-privilege API account.
- No production workloads, real Secrets, or shared cluster resources.

## Drift scenarios

| Scenario | Expected rule | Expected severity | Current evidence tier |
| --- | --- | --- | --- |
| RBAC wildcard escalation | `RADAR-RBAC-WILDCARD` | CRITICAL | Fixture-validated; controlled lab pending. |
| NetworkPolicy removal | `RADAR-NETPOL-REMOVED` | HIGH | Fixture-validated; controlled lab pending. |
| Privileged container | `RADAR-WORKLOAD-PRIVILEGED` | CRITICAL | Fixture-validated; controlled lab pending. |
| hostPath addition | `RADAR-VOLUME-HOSTPATH` | HIGH | Fixture-validated; controlled lab pending. |
| Service exposure | `RADAR-SERVICE-EXPOSURE` | HIGH | Fixture-validated; controlled lab pending. |
| Unsafe image tag | `RADAR-IMAGE-LATEST` | MEDIUM | Fixture-validated; controlled lab pending. |
| Secret-reference change | `RADAR-SECRET-REFERENCE` | MEDIUM | Fixture-validated; controlled lab pending. |
| Metadata-only control | `RADAR-METADATA-ONLY` | LOW | Fixture-validated; controlled lab pending. |

## Planned metrics

- expected versus observed rule and severity;
- true positives, false positives, and false negatives under the frozen scenario labels;
- detection and reporting latency under the formal protocol;
- explanation completeness and consistency; and
- added security context compared with raw Argo CD `OutOfSync` status.

## Evidence handling

The scenario runner records UTC timestamps, a minimal Argo CD observation, RADAR JSON, expected classification, and reset status. Local raw runs remain in the ignored `k8s-lab/evidence/` directory until reviewed. Evidence must not contain tokens, kubeconfigs, deploy keys, real cluster URLs, or real Secret values.
