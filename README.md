# Risk-Aware Security Drift Detection for GitOps-Managed Kubernetes Clusters

RADAR is a final-year Computer Networks and Cybersecurity research prototype for interpreting GitOps drift as a security signal. Argo CD can report that a Kubernetes application is OutOfSync, but raw drift status does not explain whether the change is a low-risk metadata edit or a high-risk security regression such as RBAC escalation, NetworkPolicy removal, or privileged workload execution.

RADAR means **Risk-Aware Drift Assessment for Reconciliation**.

The CLI currently uses only the Go standard library. No CLI framework is included in the foundation so the command surface stays small and easy to audit.

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
- It does not include a web dashboard yet.
- It does not use ML for risk scoring.

## Architecture Summary

RADAR uses Argo CD as the first drift source. The Go CLI collects Application status, converts OutOfSync resources into normalized findings, and writes terminal or JSON reports. Rego policies under `policies/` define the intended risk classification for normalized field-level drift fixtures. The current Argo CD Application status integration is intentionally honest: it can identify resource-level OutOfSync findings, but it does not fake field-level diff semantics.

## MVP Scope

The MVP must consume real Argo CD API data and extract or validate field-level drift before assigning final security risk. This foundation includes the REST client, normalized model, policy scaffold, report outputs, tests, CI, documentation, and safe synthetic fixtures.

## Non-Goals

- Dashboard implementation before MVP.
- Admission webhooks.
- Kubernetes controllers/operators.
- Release packaging.
- Real cluster credentials or screenshots.

## Requirements

- Go 1.22 or newer.
- Argo CD API access for real scans.
- OPA CLI for local Rego policy tests. GitHub Actions installs OPA automatically in CI.

## Configuration

RADAR accepts explicit flags and environment variables. Flags override environment variables, and environment variables override defaults.

```sh
ARGOCD_SERVER=https://argocd.example.local
ARGOCD_AUTH_TOKEN=replace-with-token
RADAR_OUTPUT=table
```

Defaults:

- `RADAR_OUTPUT` defaults to `table`.
- `ARGOCD_SERVER` has no default.
- `ARGOCD_AUTH_TOKEN` has no default.

## Example Commands

```sh
radar version
radar scan --app guestbook --server https://argocd.example.local --token replace-with-token --output table
radar scan --app guestbook --server https://argocd.example.local --token replace-with-token --output json
radar scan --app guestbook --output json
go run ./cmd/radar scan --fixture testdata/argocd/application_outofsync.json --output table
```

The last command uses a sanitized local fixture for development and documentation.

## Example Output

```text
RADAR Drift Report
Application: guestbook
Project: default
Sync Status: OutOfSync
Health Status: Healthy

Findings:

| Severity | Score | Resource | Change | Reason | Recommendation |
| -------- | ----- | -------- | ------ | ------ | -------------- |
| INFO | 0 | apps/v1/Deployment/demo/guestbook | unknown unknown | Argo CD reports this resource as OutOfSync, but field-level diff data is unavailable. | Fetch field-level diff data before assigning a security severity. |
```

## Security Notice

Do not commit Argo CD tokens, kubeconfigs, real cluster URLs, screenshots with sensitive data, or real secrets. RADAR must not print tokens or include them in errors. Test data must stay synthetic and sanitized.

## Current Implementation Status

- Go CLI skeleton exists.
- Argo CD Application API client exists and is tested with `httptest`.
- Resource-level OutOfSync findings are produced from Argo CD Application status.
- Rego policies and tests are scaffolded against synthetic field-level fixtures.
- Field-level Argo CD diff extraction is not implemented yet and is required for the MVP.

## Roadmap

1. Foundation: CLI, client, model, policies, reports, CI, docs.
2. MVP: real Argo CD field-level drift extraction and scenario validation.
3. Evaluation: local Kubernetes and Argo CD lab, experiment logs, false positive and false negative tracking.
4. Post-MVP: minimal dashboard, SARIF export, webhooks, packaging, and public release preparation.

## License

No license is applied while this repository is private. Apache-2.0 is recommended when the repository is made public, but licensing will be finalized at public release.
