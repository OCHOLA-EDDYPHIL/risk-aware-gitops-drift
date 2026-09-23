# Contributing to RADAR

RADAR welcomes focused contributions to field-level drift extraction, deterministic Rego policies, evidence validation, resettable synthetic scenarios, and practitioner documentation. It remains a bounded research prototype rather than a general Kubernetes security platform.

## Before Changing Behavior

Read [Architecture](docs/architecture.md), [Policy Authoring](docs/policy-authoring.md), [Evidence and Results](docs/evidence-and-results.md), and [Limitations](docs/limitations.md). A change must preserve these invariants:

- resource-level `OutOfSync` status alone never receives a security severity;
- malformed or unavailable field evidence fails closed at INFO;
- findings are deterministic for the same normalized input and policy;
- policy decisions explain the resource, exact field change, severity, reason, and recommendation;
- RADAR interprets evidence but does not reconcile or remediate resources;
- fixture, controlled-lab, and formal-evaluation evidence remain distinct; and
- historical research evidence and its checksums remain immutable.

Keep proposals narrow. Describe the exact resource, operation, JSON Pointer, values, intended decision, negative cases, and claim boundary. New policies should not be described as evaluated until a separately frozen protocol has actually been executed.

## Development Setup

Required tools are Go 1.24.0 and, for policy tests, OPA 1.17.1. The full static lab validation also uses `kubectl` and `shellcheck`.

```sh
make fmt-check
make vet
make test
make race
make build
make docs-check
make release-check
make rego-test
make policy-integration-test
make protocol-check
make lab-static-check
```

Do not weaken a test, sanitizer, context guard, reset assertion, or evidence validator merely to make a change pass. Add focused positive, negative, malformed-input, and benign-overlap tests for behavior changes.

## Policies and Scenarios

Policy rules must match the narrowest evidence-supported condition. Impact and likelihood are ordinal values in the project's transparent matrix, not probabilities. Recommendations must remain bounded and must not imply automatic remediation.

A new scenario needs a synthetic baseline, exactly one controlled mutation, declared ground truth, a reset assertion, and sanitized evidence. It does not become part of the existing formal corpus. Extending empirical claims requires a new frozen protocol and provenance chain.

## Documentation and Claims

Document stable implemented behavior and material limitations. Do not add temporary status pages, speculative roadmaps, or demonstrations that imply broader validation than exists. Use the evidence-tier vocabulary: proposed, implemented, fixture-validated, controlled-lab observed, and formally evaluated.

The safe summary of current results is:

> In a frozen synthetic evaluation of seven selected security scenarios and one metadata-only control, RADAR detected all 70 declared security runs, classified none of the ten controls at MEDIUM or above, and reset successfully after all 80 observations.

Do not generalize this to universal accuracy, production readiness, malicious-intent detection, or zero false positives outside the declared controls.

## Security and Conduct

Use only synthetic data. Never submit tokens, kubeconfigs, private endpoints, real Secrets, private keys, production manifests, or unsanitized evidence. Report vulnerabilities through the private process in [SECURITY.md](SECURITY.md), and follow [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md) in all project spaces.

No public license grant applies until the relevant license files are present. See [Licensing Boundaries](docs/licensing.md).
