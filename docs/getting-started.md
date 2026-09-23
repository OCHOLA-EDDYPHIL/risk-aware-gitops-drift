# Getting Started

This guide covers a fixture-based scan and a read-only live Argo CD scan. The fixture path is the recommended first run because it requires no Kubernetes cluster and cannot mutate infrastructure.

## Requirements

- Go 1.24.0.
- OPA 1.17.1 available as `opa` on `PATH`.
- Git LFS 3.x only when retrieving immutable evidence archives.
- Argo CD API access only for a live scan.

Verify the local tools:

```sh
go version
opa version
```

## Build

```sh
make build
./bin/radar version
```

Build metadata is injected from the current immutable commit. A source build without release metadata reports `dev`.

### Release Archive Layout

After a licensed release exists, its Linux archive is self-contained for fixture scans. It includes the `radar` binary, `policies/risk.rego`, citation metadata, licensing information, and third-party notices. Extract the archive, enter its directory, and verify the build identity before scanning:

```sh
./radar version
./radar scan \
  --fixture path/to/sanitized-scan-bundle.json \
  --policy policies/risk.rego \
  --output table
```

Verify the archive against the published `SHA256SUMS` before execution. No release archive exists yet; source builds remain the current reproducible path.

## Fixture-Based Scan

Run a privileged-container example:

```sh
./bin/radar scan \
  --fixture testdata/argocd/scan_bundle_privileged.json \
  --policy policies/risk.rego \
  --output json
```

The expected classified finding has rule `RADAR-WORKLOAD-PRIVILEGED`, path `/spec/template/spec/containers/0/securityContext/privileged`, before value `false`, after value `true`, and severity `CRITICAL` with score `100`.

Run the benign control:

```sh
./bin/radar scan \
  --fixture testdata/argocd/scan_bundle_metadata_only.json \
  --policy policies/risk.rego \
  --output json
```

The expected selected decision is `RADAR-METADATA-ONLY`, `LOW`, score `4`. The study defines MEDIUM or above as security-positive, so this control is not a security-positive result.

Run the resource-status-only example:

```sh
./bin/radar scan \
  --fixture testdata/argocd/application_outofsync.json \
  --policy policies/risk.rego \
  --output table
```

The expected result is INFO because the fixture does not contain field-level desired/live state.

## Configuration Precedence

Flags override environment variables, which override defaults.

| Purpose | Flag | Environment | Default |
| --- | --- | --- | --- |
| Argo CD server | `--server` | `ARGOCD_SERVER` | none |
| Argo CD token | `--token` | `ARGOCD_AUTH_TOKEN` | none |
| Policy file | `--policy` | `RADAR_POLICY_PATH` | `policies/risk.rego` |
| Output | `--output` | `RADAR_OUTPUT` | `table` |
| Overall timeout | `--timeout` | none | `30s` |

The token flag exists for compatibility, but environment-based delivery is safer because command arguments can be visible to other processes and shell history.

## Read-Only Live Scan

Create an Argo CD account limited to reading the intended Application, project, and managed-resource data. Do not use the administrator account.

```sh
export ARGOCD_SERVER=https://argocd.example.local
export ARGOCD_AUTH_TOKEN='replace-with-a-short-lived-read-only-token'
export RADAR_POLICY_PATH=policies/risk.rego

./bin/radar scan --app guestbook --output json >radar-result.json
```

RADAR performs two HTTP GET requests:

- `/api/v1/applications/{name}`
- `/api/v1/applications/{name}/managed-resources`

The scanner does not call Kubernetes directly, synchronize the Application, or mutate a resource.

## Validation Suite

The deterministic suite is:

```sh
make fmt-check
make vet
make test
make race
make build
make rego-test
make policy-integration-test
make protocol-check
make docs-check
make release-check
```

The full lab static suite also requires `kubectl` and `shellcheck`:

```sh
make lab-static-check
```

The resettable Kubernetes laboratory is a research environment, not a prerequisite for using fixture mode. It can run on any compatible Linux and Docker host. Read `k8s-lab/README.md` and its safety boundary before starting it.

## Next Steps

- Read [Policy Authoring](policy-authoring.md) before adding a rule.
- Read [Evidence and Results](evidence-and-results.md) before interpreting the formal corpus.
- Read [Limitations](limitations.md) before applying the approach outside the selected scenarios.
- Use [Troubleshooting](troubleshooting.md) when a scan or build fails.
