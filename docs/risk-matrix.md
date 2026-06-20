# Risk Matrix

| Severity | Score Range | Meaning |
| -------- | ----------- | ------- |
| CRITICAL | 90-100 | Drift creates direct or likely privilege escalation or container breakout risk. |
| HIGH | 70-89 | Drift weakens isolation, exposes workloads, or enables node-level access. |
| MEDIUM | 40-69 | Drift changes sensitive runtime inputs or weakens supply-chain controls. |
| LOW | 10-39 | Drift is metadata-only or operationally relevant with limited direct security impact. |
| INFO | 0-9 | Drift is known only at resource level and needs field-level evidence. |

| Scenario | Expected Severity |
| -------- | ----------------- |
| RBAC privilege escalation | CRITICAL |
| NetworkPolicy removal | HIGH |
| Privileged container introduction | CRITICAL |
| hostPath volume addition | HIGH |
| Service exposure through NodePort or LoadBalancer | HIGH |
| Unsafe image tag change | MEDIUM |
| Secret reference change | MEDIUM |
| Metadata-only label or annotation change | LOW |
| Argo CD resource-level OutOfSync without field-level diff | INFO |
