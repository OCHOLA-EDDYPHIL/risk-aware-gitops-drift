# RADAR Rego Policies

RADAR policies live under the `radar.risk` package and evaluate normalized atomic drift findings. Decisions include a stable rule ID, impact, likelihood, normalized score, severity, reason, and recommendation. The frozen model and rationale are documented in `docs/risk-matrix.md`.

Run policy tests with:

```sh
opa test policies testdata
```

The prototype uses the OPA CLI as an external adapter. The Go module does not embed OPA, keeping the policy boundary explicit and independently testable.

Fixture success is policy-unit evidence, not controlled-lab or formal-evaluation evidence.
