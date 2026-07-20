# Research Traceability

| Research objective | Implemented component or durable artifact | Evidence interface | Report chapter |
| --- | --- | --- | --- |
| Identify security-relevant GitOps drift | Argo CD client and deterministic managed-resource comparison | Atomic resource, operation, path, before/after, confidence and observation fields | Ch3, Ch4, Ch5 |
| Classify selected drift by security risk | OPA/Rego policy set and frozen risk matrix | Rule identifier, impact, likelihood, score, severity, reason and recommendation | Ch4, Ch5 |
| Produce explainable and reproducible evidence | Terminal/JSON reports and the sanitized evidence schema | Stable finding identifiers, matched rules, immutable archives, checksums and indexes | Ch4, Ch5 |
| Compare RADAR interpretation with raw Argo CD drift status | Isolated resettable research lab and controlled scenario set | Application status, managed-resource evidence, RADAR result and verified reset record | Ch5 |
