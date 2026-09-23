# Policy Authoring

RADAR evaluates one normalized atomic finding at a time with OPA/Rego. A policy decision must be deterministic, evidence-bound, and understandable to a reviewer.

## Input Contract

The relevant input fields are:

- `resource.group`, `resource.version`, `resource.kind`, `resource.namespace`, and `resource.name`;
- `change.operation`: `add`, `remove`, `replace`, or `unknown`;
- `change.path`: JSON Pointer path;
- `change.before` and `change.after`: typed JSON values;
- `change.confidence`: normally `field-level` or `resource-status-only`;
- `evidenceSource` and `observedAt`.

Argo CD wire types do not enter the policy contract. The Go drift layer normalizes them first.

## Decision Contract

Each match returned by `data.radar.risk.findings` must contain:

```json
{
  "ruleId": "RADAR-EXAMPLE",
  "impact": 3,
  "likelihood": 3,
  "severity": "MEDIUM",
  "score": 36,
  "reason": "Explain the observed field-level condition.",
  "recommendation": "Describe a bounded and reviewable response."
}
```

RADAR selects the highest score, breaks equal-score ties by rule identifier, and retains all matched rule identifiers. A rule must not depend on iteration order, external state, network access, or the current time.

## Authoring Rules

1. Match the narrowest resource, operation, path, and value condition supported by evidence.
2. Do not assign a security severity from `OutOfSync` alone.
3. Keep insufficient field evidence at INFO.
4. Treat impact and likelihood as ordinal values in this model, not probabilities.
5. State what the rule does not prove. For example, NodePort expands exposure relative to ClusterIP but does not prove public Internet reachability.
6. Provide a direct reason and a recommendation that does not imply automatic remediation.
7. Add positive, negative, malformed-input, benign-overlap, and equal-score tests.

## Development Tests

Run the Rego suite:

```sh
make rego-test
```

Run the full stored-bundle path through the real OPA CLI:

```sh
make policy-integration-test
```

The formal evaluation is frozen. Changing a policy, score, threshold, or ground-truth mapping does not rewrite earlier results. It creates a new implementation and requires a separately declared evaluation before new empirical claims are made.

## Adding a Scenario

A new policy rule does not automatically become a formally evaluated scenario. A formal extension requires, before collection:

- a synthetic baseline and one isolated mutation;
- predeclared security relevance, rule, impact, likelihood, score, and severity;
- positive and benign controls;
- a reset assertion for every changed field;
- a decision-complete protocol and declared run identifiers;
- a new frozen source, policy, risk-matrix, and environment provenance chain.

See [Risk Matrix](risk-matrix.md) for the current evaluated mapping and [Evidence and Results](evidence-and-results.md) for evidence tiers.
