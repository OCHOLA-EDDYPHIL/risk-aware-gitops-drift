# RADAR Risk Matrix

## Model

RADAR uses a transparent 5×5 impact-likelihood model for the selected controlled scenarios:

```text
normalized score = impact × likelihood × 4
```

| Severity | Score | Interpretation in the prototype |
|---|---:|---|
| CRITICAL | 80–100 | Direct privilege expansion or loss of a core workload isolation boundary |
| HIGH | 50–79 | Material weakening of network, node, or exposure controls |
| MEDIUM | 20–49 | Sensitive runtime-input or artifact-reference drift requiring review |
| LOW | 1–19 | Selected drift with limited direct security impact |
| INFO | 0 | Field-level evidence is unavailable; security severity is not assigned |

Impact estimates the potential consequence to confidentiality, integrity, availability, privilege boundaries, or attack surface. Likelihood estimates how directly the selected drift creates the stated exposure in the controlled testbed. The multiplication is an ordinal prioritization mechanism, not a quantitative probability model.

## Frozen scenario mapping

| Rule ID | Scenario | Impact | Likelihood | Score | Severity |
|---|---|---:|---:|---:|---|
| `RADAR-RBAC-WILDCARD` | Role/ClusterRole gains wildcard privileges | 5 | 5 | 100 | CRITICAL |
| `RADAR-WORKLOAD-PRIVILEGED` | Container changes to `privileged: true` | 5 | 5 | 100 | CRITICAL |
| `RADAR-NETPOL-REMOVED` | Intended NetworkPolicy is removed | 4 | 4 | 64 | HIGH |
| `RADAR-VOLUME-HOSTPATH` | Workload gains a `hostPath` volume | 5 | 3 | 60 | HIGH |
| `RADAR-SERVICE-EXPOSURE` | Service changes from ClusterIP to NodePort | 4 | 4 | 64 | HIGH |
| `RADAR-IMAGE-LATEST` | Versioned image changes to `latest` | 3 | 3 | 36 | MEDIUM |
| `RADAR-SECRET-REFERENCE` | Workload Secret reference changes | 4 | 2 | 32 | MEDIUM |
| `RADAR-METADATA-ONLY` | Non-security metadata changes | 1 | 1 | 4 | LOW |
| `RADAR-INSUFFICIENT-EVIDENCE` | Only resource-level drift is available | 0 | 0 | 0 | INFO |

The mapping is frozen before formal evaluation. Changing a rule, score, threshold, or rationale after formal runs begin requires a versioned replacement experiment rather than rewriting earlier results.

## Rationale boundaries

- Kubernetes RBAC good practices warn against wildcard permissions and privilege-escalation paths.
- Kubernetes security-context guidance describes privileged containers as receiving capabilities equivalent to root on the host for relevant controls.
- NetworkPolicy removal eliminates an intended traffic-isolation declaration; RADAR does not claim full reachability analysis.
- Kubernetes warns that `hostPath` presents security risks because it mounts host filesystem content into a Pod.
- NodePort expands the Service exposure surface relative to ClusterIP; RADAR does not claim public internet reachability.
- The `latest` tag is mutable and weakens reproducibility; RADAR does not perform signature or provenance verification.
- A Secret-reference change alters which sensitive runtime object is consumed; RADAR does not inspect Secret contents or claim compromise.
- Metadata is the benign control and remains LOW unless a future, separately evaluated model establishes security-sensitive metadata semantics.

## Sources

- National Institute of Standards and Technology. [*Guide for Conducting Risk Assessments*, SP 800-30 Rev. 1](https://nvlpubs.nist.gov/nistpubs/Legacy/SP/nistspecialpublication800-30r1.pdf) (2012).
- Kubernetes documentation: [RBAC good practices](https://kubernetes.io/docs/concepts/security/rbac-good-practices/), [security contexts](https://kubernetes.io/docs/tasks/configure-pod-container/security-context/), [NetworkPolicies](https://kubernetes.io/docs/concepts/services-networking/network-policies/), [`hostPath` volumes](https://kubernetes.io/docs/concepts/storage/volumes/#hostpath), [Services](https://kubernetes.io/docs/concepts/services-networking/service/), [images](https://kubernetes.io/docs/concepts/containers/images/), and [Secrets](https://kubernetes.io/docs/concepts/configuration/secret/).
- The peer-reviewed GitOps, policy-as-code, networking-security, and Kubernetes-misconfiguration works listed in the project's academic source register.
