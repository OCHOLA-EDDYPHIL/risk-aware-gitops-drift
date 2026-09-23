# Licensing Boundaries

The repository separates software, public technical material, research evidence, and private academic artifacts because they have different publication and copyright considerations.

## Intended Public Model

Subject to written institutional or supervisor clearance:

- source code, Rego policies, shell scripts, tests, and machine-readable configuration are intended for Apache License 2.0;
- public technical documentation and the sanitized research-evidence corpus are intended for Creative Commons Attribution 4.0 International;
- third-party components remain under their own licenses;
- private proposals, reports, defense material, institutional templates, correspondence, and assessment records remain outside this repository and outside its public license grants.

This document describes boundaries; it is not itself a license grant. A public license applies only when the corresponding license file and repository notice are present.

## Evidence Attribution

Sanitized evidence records should be attributed to Ochola Eddyphil Odhiambo and RADAR—Risk-Aware Drift Assessment for Reconciliation. Reusers must retain provenance, checksums, evidence-tier labels, and material limitations. Modifying a record or policy invalidates claims that it is the original frozen observation.

## Third-Party Material

The project depends on Go modules and invokes external tools including OPA, Kubernetes, Minikube, Argo CD, Docker, kubectl, Git LFS, and shell utilities. Their names identify interoperability and do not imply endorsement. See [Third-Party Notices](../THIRD_PARTY_NOTICES.md).
