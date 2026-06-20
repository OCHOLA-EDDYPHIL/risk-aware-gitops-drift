# RADAR Rego Policies

RADAR policies live under the `radar.risk` package and evaluate normalized drift findings. The initial policy scaffold classifies synthetic drift fixtures into CRITICAL, HIGH, MEDIUM, LOW, and INFO severities.

Run policy tests with:

```sh
opa test policies testdata
```

The foundation uses the OPA CLI as an external adapter. The Go module does not embed OPA yet, keeping the prototype small while the policy interface stabilizes.
