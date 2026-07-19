# Development Requirements

Changes must preserve deterministic findings, fail-closed behavior when field-level evidence is unavailable, and the separation between fixture validation and controlled-lab evidence. Update durable documentation when system behavior, policy semantics, the risk model, or the evaluation protocol changes.

## Tests Required

Run:

```sh
make fmt
make test
make build
```

Run `make rego-test` when the OPA CLI is installed. GitHub Actions installs OPA and runs policy tests in CI.

## No Secrets Rule

Do not commit tokens, kubeconfigs, real cluster URLs, screenshots with sensitive data, or real secrets. Use synthetic fixtures only.

## Lab Safety

Lab commands must use the explicit `radar-lab` profile and context. Use only synthetic workloads and dummy Secret values, keep Argo CD access least-privileged, and verify baseline reset after every scenario.
