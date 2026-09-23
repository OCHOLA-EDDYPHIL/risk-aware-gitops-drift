# Limitations and Claim Boundaries

RADAR is a research prototype. The following limits are material, not footnotes.

## Evaluated Scope

- One synthetic application.
- One single-node Minikube cluster.
- One pinned Argo CD configuration.
- Seven hand-authored security scenarios and one metadata-only control.
- Ten deterministic repetitions per scenario.
- One project-defined impact–likelihood matrix.

The scenario distribution was balanced by protocol and does not estimate real Kubernetes drift prevalence.

## Detection Limits

- Rules recognize selected resource, path, operation, and value patterns; they do not discover arbitrary attacks or misconfigurations.
- Severity values were not independently validated by a panel of security assessors.
- NetworkPolicy removal is detected, but RADAR does not perform network reachability analysis.
- NodePort or LoadBalancer drift indicates broader Service exposure, not proven Internet reachability.
- Image-tag drift is detected, but RADAR does not verify signatures, provenance, digests, or registry trust.
- Secret-reference drift is detected without inspecting Secret contents or proving compromise.
- Metadata was a benign control; real environments can attach security meaning to labels and annotations.
- Kubernetes list reordering and semantic equivalence can produce JSON-level differences that require domain-specific interpretation.

## Operational Limits

- RADAR invokes the local OPA CLI once per atomic finding. This is simple and auditable but not optimized for high-throughput scanning.
- The CLI scans one named Argo CD Application per invocation.
- There is no long-running service, event stream, persistence layer, dashboard, tenancy model, alert routing, or automatic remediation.
- The prototype was not evaluated for large Applications, concurrent drift, API degradation, multiple clusters, multiple distributions, or long-running operation.
- Timing used wall-clock timestamps with one-second resolution and is not a throughput or service-level measurement.

## Research Limits

The formal result of 70/70 selected security detections and 0/10 controls classified MEDIUM or above is valid only for the frozen scenario set and protocol. It must not be shortened to claims such as:

- “RADAR is 100% accurate.”
- “RADAR has zero false positives.”
- “RADAR detects malicious Kubernetes drift.”
- “RADAR is production-ready.”
- “RADAR prevents configuration drift.”

Safe wording is:

> In a frozen synthetic evaluation of seven selected security scenarios and one metadata-only control, RADAR detected all 70 declared security runs, classified none of the ten controls at MEDIUM or above, and reset successfully after all 80 observations.

## Appropriate Uses

RADAR is suitable for:

- studying field-level Argo CD managed-resource evidence;
- testing deterministic Rego interpretation of controlled changes;
- demonstrating fail-closed security-research workflows;
- extending the scenario set under a newly frozen protocol;
- evaluating whether the approach is useful in another organization's controlled environment.

It should not be deployed as a production security control without broader policy review, independent severity validation, scale and failure testing, operational integration, and a defined support model.
