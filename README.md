# RADAR: Explainable Security Interpretation for GitOps Drift

RADAR—**Risk-Aware Drift Assessment for Reconciliation**—is a Go research prototype that turns Argo CD desired-versus-live resource evidence into deterministic, field-level security findings.

Argo CD remains responsible for GitOps comparison and reconciliation. RADAR is read-only: it retrieves Application and managed-resource data, extracts atomic `add`, `remove`, and `replace` changes, evaluates them with OPA/Rego, and reports the affected resource, JSON Pointer, before/after values, severity, reason, and recommendation.

RADAR began as a final-year cybersecurity research project by Ochola Eddyphil Odhiambo. It is intended for reproducible research and practitioner experimentation, not production enforcement.

## Why It Exists

`OutOfSync` establishes that a Git-managed resource differs from the live cluster. It does not by itself answer whether the exact difference is a metadata edit, a removed NetworkPolicy, a wildcard RBAC rule, or privileged workload execution.

RADAR adds that bounded interpretation:

```text
Git desired state + Kubernetes live state
                    │
                    ▼
Argo CD Application + managed-resource evidence
                    │
                    ▼
Atomic field changes: resource + operation + JSON Pointer + values
                    │
                    ▼
OPA/Rego rules + transparent impact–likelihood matrix
                    │
                    ▼
Explainable table or JSON findings
```

If Argo CD does not provide usable field-level state, RADAR returns `INFO`. It does not infer a security severity from resource-level status alone.

## What Is Implemented

- Argo CD Application and managed-resource REST collection.
- Deterministic desired-to-live JSON comparison with Kubernetes-owned noise removed through a narrow allow-list.
- Stable atomic findings with JSON Pointer paths and typed before/after values.
- OPA/Rego policies for seven selected security conditions and one metadata-only control.
- Deterministic decision selection with all matched rule identifiers retained.
- Human-readable table and machine-readable JSON output.
- An isolated, explicitly guarded, resettable Minikube and Argo CD research lab.
- Fail-closed evidence preparation, schema validation, checksums, and immutable Git LFS archives.
- A frozen 80-run controlled evaluation corpus.

RADAR is not an admission controller, Kubernetes operator, runtime detector, SIEM, remediation engine, production multi-cluster service, or general vulnerability scanner. It has no dashboard and does not use machine learning.

## Quickstart with Sanitized Evidence

The fastest safe path exercises the complete extraction-to-report pipeline without starting a cluster.

Requirements:

- Go 1.24.0.
- OPA 1.17.1 available as `opa` on `PATH`.

```sh
git clone https://github.com/OCHOLA-EDDYPHIL/risk-aware-gitops-drift.git
cd risk-aware-gitops-drift
make build
./bin/radar scan \
  --fixture testdata/argocd/scan_bundle_privileged.json \
  --policy policies/risk.rego \
  --output table
```

The representative finding identifies:

```text
resource:  apps/v1/Deployment/radar-demo/radar-demo
operation: replace
path:      /spec/template/spec/containers/0/securityContext/privileged
values:    false → true
rule:      RADAR-WORKLOAD-PRIVILEGED
decision:  CRITICAL / 100
```

Use JSON output when integrating with other tools:

```sh
./bin/radar scan \
  --fixture testdata/argocd/scan_bundle_metadata_only.json \
  --policy policies/risk.rego \
  --output json
```

Stored fixtures are **fixture-validated evidence**, not live-cluster observations. See [Getting Started](docs/getting-started.md) for expected behavior and troubleshooting.

## Scan a Live Argo CD Application

Use a least-privilege Argo CD account that can read only the intended Application, project, and managed-resource data. Prefer environment variables so credentials do not enter shell history or process arguments.

```sh
export ARGOCD_SERVER=https://argocd.example.local
export ARGOCD_AUTH_TOKEN='replace-with-a-short-lived-read-only-token'
export RADAR_POLICY_PATH=policies/risk.rego

./bin/radar scan --app guestbook --output table
```

Flags override environment variables. `--timeout` bounds the complete scan and defaults to `30s`. See [Getting Started](docs/getting-started.md) for configuration precedence and [Security](SECURITY.md) before connecting to a cluster.

## Evaluated Results

The formal corpus used seven security scenarios and one metadata-only control, each repeated ten times under one frozen protocol and implementation revision.

| Measure | Result |
| --- | ---: |
| Declared, completed, and reset-verified observations | 80 / 80 |
| Selected security scenarios detected | 70 / 70 |
| Metadata controls classified MEDIUM or above | 0 / 10 |
| Exact predeclared severity matches | 80 / 80 |
| Findings with all required explanation fields | 80 / 80 |
| Median / p95 time to detect | 4 s / 4 s |
| Median / p95 processing latency | 0 s / 1 s |

These are **formally evaluated results for the declared synthetic scenario set**, not evidence of universal accuracy. The same deterministic rules generated every repetition; expected severities came from the project's frozen risk matrix; and timing used one-second timestamps. The experiment used one synthetic application in one single-node Minikube cluster and one pinned Argo CD configuration.

Read [Evidence and Results](docs/evidence-and-results.md) for denominators and provenance, and [Limitations](docs/limitations.md) before quoting any metric.

## Policies and Risk Model

The policy catalogue covers:

- wildcard RBAC expansion;
- NetworkPolicy removal;
- privileged-container activation;
- `hostPath` addition;
- Service exposure from ClusterIP to NodePort or LoadBalancer;
- a versioned image changed to `latest`;
- a changed Secret reference;
- metadata-only drift as a LOW control;
- insufficient field evidence as INFO.

The 5 × 5 model is transparent and reviewable, but it is not a probability model or a universal organizational risk rating. See [Risk Matrix](docs/risk-matrix.md) and [Policy Authoring](docs/policy-authoring.md).

## Research Evidence

Small summaries and run records are ordinary Git objects. Immutable `.tar.zst` archives use selective Git LFS. A full evidence checkout requires:

```sh
git lfs install
git lfs pull
```

The formal corpus is under `research/evidence/formal-evaluation-v1/`. Archive checksums, schema validation, protocol bindings, and result derivation are documented in [Evidence and Results](docs/evidence-and-results.md).

## Documentation

- [Getting Started](docs/getting-started.md)
- [Architecture](docs/architecture.md)
- [Policy Authoring](docs/policy-authoring.md)
- [Risk Matrix](docs/risk-matrix.md)
- [Evidence and Results](docs/evidence-and-results.md)
- [Limitations](docs/limitations.md)
- [Troubleshooting](docs/troubleshooting.md)
- [Research Traceability](docs/research-traceability.md)
- [Contributing](CONTRIBUTING.md)
- [Security](SECURITY.md)
- [Code of Conduct](CODE_OF_CONDUCT.md)
- [Citation](CITATION.cff)
- [Third-Party Notices](THIRD_PARTY_NOTICES.md)

## Contributing and Security

Contributions are welcome when they preserve deterministic results, fail-closed evidence handling, explicit evidence tiers, and the separation between interpretation and reconciliation. Start with [CONTRIBUTING.md](CONTRIBUTING.md).

Do not open a public issue containing credentials, kubeconfigs, private endpoints, real Secrets, or unsanitized evidence. Follow [SECURITY.md](SECURITY.md) for private reporting.

## License Status

No public license grant applies unless the relevant license files are present in the repository. The intended source, documentation, evidence, and academic-artifact boundaries are described in [Licensing Boundaries](docs/licensing.md). Private academic masters are not part of this repository.
