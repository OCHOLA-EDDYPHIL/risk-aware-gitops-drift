# RADAR Demonstration Sequence

1. State the research problem: raw GitOps drift does not express security impact.
2. Show the Go collector, normalized drift model, frozen Rego policy, and terminal/JSON report boundary.
3. Run `radar version` and the sanitized Application-only fixture to demonstrate the honest INFO fallback.
4. Run the sanitized scan bundle to demonstrate fixture-validated extraction, policy evaluation, and explanation without calling it live evidence.
5. Show the pinned `radar-lab` guardrails and confirm the active Kubernetes context is not used implicitly.
6. After the lab preflight passes, run one guarded scenario and show Argo CD `OutOfSync`, the expected RADAR rule, and the verified baseline reset.
7. Run the Go and Rego checks.
8. Close by separating fixture validation, controlled-lab observation, and the later formal repeated-run evaluation.

Fixture commands:

```sh
go run ./cmd/radar scan --fixture testdata/argocd/application_outofsync.json --output table
go run ./cmd/radar scan --fixture testdata/argocd/scan_bundle_privileged.json --output json
```

Controlled-lab command after setup:

```sh
k8s-lab/scripts/run-scenario.sh --context radar-lab --scenario privileged-container --repetition 1
```
