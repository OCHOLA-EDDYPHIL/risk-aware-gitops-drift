# Risk-Aware Security Drift Detection for GitOps-Managed Kubernetes Clusters

RADAR is a final-year Computer Networks and Cybersecurity research prototype for interpreting GitOps drift as a security signal. Argo CD can report that a Kubernetes application is OutOfSync, but raw drift status does not explain whether the change is a low-risk metadata edit or a high-risk security regression such as RBAC escalation, NetworkPolicy removal, or privileged workload execution.

RADAR means **Risk-Aware Drift Assessment for Reconciliation**.

The CLI deliberately avoids a CLI framework so the command surface stays small and easy to audit. The Go implementation uses a focused JSON-diff dependency for deterministic desired-versus-live comparison and invokes the local OPA CLI for Rego evaluation.

## What RADAR Does

- Provides a Go CLI named `radar`.
- Consumes Argo CD Application API data over HTTP REST.
- Normalizes drift into a small internal model.
- Evaluates normalized drift with OPA/Rego policy scaffolding.
- Produces explainable terminal and JSON reports.

## What RADAR Does Not Do

- It is not a full GitOps platform.
- It is not a Kubernetes admission controller.
- It is not a Kubernetes operator or CRD system.
- It is not a SIEM.
- It does not include a web dashboard.
- It does not use ML for risk scoring.

## Architecture Summary

RADAR uses Argo CD as the first drift source. The Go CLI retrieves Application and managed-resource state, compares normalized desired and live Kubernetes objects, evaluates each atomic change with Rego policies under `policies/`, and writes terminal or JSON reports. If only Application status is available, RADAR emits an INFO finding and does not invent field-level evidence or a security severity.

## MVP Scope

The MVP must consume real Argo CD API data and extract or validate field-level drift before assigning final security risk. This foundation includes the REST client, normalized model, policy scaffold, report outputs, tests, CI, documentation, and safe synthetic fixtures.

## Non-Goals

- Dashboard implementation.
- Admission webhooks.
- Kubernetes controllers/operators.
- Production deployment manifests or multi-cluster operation.
- Release packaging.
- Real cluster credentials or screenshots.

## Requirements

- Go 1.24.0.
- Argo CD API access for real scans.
- OPA CLI for local Rego policy tests. GitHub Actions installs OPA automatically in CI.

## Configuration

RADAR accepts explicit flags and environment variables. Flags override environment variables, and environment variables override defaults.

```sh
ARGOCD_SERVER=https://argocd.example.local
ARGOCD_AUTH_TOKEN=replace-with-token
RADAR_OUTPUT=table
RADAR_POLICY_PATH=policies/risk.rego
```

Defaults:

- `RADAR_OUTPUT` defaults to `table`.
- `RADAR_POLICY_PATH` defaults to `policies/risk.rego`.
- `ARGOCD_SERVER` has no default.
- `ARGOCD_AUTH_TOKEN` has no default.

Equivalent command flags are `--server`, `--token`, `--output`, and `--policy`. `--timeout` limits the complete scan and defaults to `30s`. Flags take precedence over environment variables.

## Example Commands

```sh
radar version
radar scan --app guestbook --server https://argocd.example.local --token replace-with-token --output table
radar scan --app guestbook --server https://argocd.example.local --token replace-with-token --policy policies/risk.rego --output json
radar scan --app guestbook --output json
go run ./cmd/radar scan --fixture testdata/argocd/application_outofsync.json --output table
go run ./cmd/radar scan --fixture testdata/argocd/scan_bundle_privileged.json --output json
```

The fixture mode supports two sanitized formats. A legacy Application-only fixture demonstrates the explicit INFO fallback when field-level evidence is unavailable. A scan-bundle fixture contains both Application and managed-resource responses and exercises deterministic extraction, policy evaluation, and reporting without claiming that a live cluster was observed. Fixtures are development evidence, not experimental results.

## Example Output

```text
RADAR Drift Report
Application: guestbook
Project: default
Sync Status: OutOfSync
Health Status: Healthy

Findings:

| Severity | Score | Rule | Resource | Change | Reason | Recommendation |
| -------- | ----- | ---- | -------- | ------ | ------ | -------------- |
| INFO | 0 | RADAR-INSUFFICIENT-EVIDENCE | apps/v1/Deployment/demo/guestbook | unknown unknown | Argo CD reports resource-level drift but field-level evidence is unavailable. | Collect valid field-level desired and live state before assigning security risk. |
```

## Security Notice

Do not commit Argo CD tokens, kubeconfigs, real cluster URLs, screenshots with sensitive data, or real secrets. RADAR must not print tokens or include them in errors. Test data must stay synthetic and sanitized.

## Current Implementation Status

- The Go CLI retrieves Argo CD Application and managed-resource API data.
- Desired-versus-live state is normalized into deterministic atomic changes.
- Frozen Rego rules classify the selected security scenarios with explainable impact, likelihood, score, and recommendation fields.
- Terminal and JSON reports expose the selected rule and retain all matched rule IDs in JSON.
- Sanitized scan bundles validate the integrated extraction-to-report path.
- Controlled-lab validation and the formal repeated-run evaluation remain outstanding; fixture results must not be presented as live experimental evidence.

## License

No license is currently applied to this private repository.
