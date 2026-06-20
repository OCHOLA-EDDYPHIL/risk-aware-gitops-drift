# Backlog

This backlog mirrors the GitHub issues used for RADAR implementation tracking. Issues use minimal metadata: milestone, type, priority, chapter link, and evidence needed.

## Completed Foundation Setup

The initial Foundation setup work was completed by PR #8 and closed issues #1-#7. Do not recreate those issues.

| Issue | Milestone | Type | Priority | Evidence |
| ----- | --------- | ---- | -------- | -------- |
| #1 Set up Go CLI project structure | Foundation | Backend | P0 | Code, Test Log |
| #2 Implement Argo CD Application API client | Foundation | Backend | P0 | Code, Test Log |
| #3 Implement normalized drift model | Foundation | Architecture | P0 | Code, Diagram |
| #4 Implement OPA/Rego policy scaffold | Foundation | Policy | P0 | Code, Test Log |
| #5 Implement terminal and JSON reporting | Foundation | Backend | P0 | Screenshot, Code |
| #6 Add CI checks | Foundation | CI | P0 | Test Log |
| #7 Add documentation skeleton | Foundation | Docs | P0 | Code |

## Active Issues

| Issue | Milestone | Type | Priority | Chapter | Evidence Needed |
| ----- | --------- | ---- | -------- | ------- | --------------- |
| #9 Audit merged foundation baseline | Foundation | Docs | P1 | None | Documentation |
| #10 Implement field-level drift extraction strategy | MVP | Argo CD | P0 | Ch4 | Code |
| #11 Normalize Argo CD diff output into RADAR drift model | MVP | Backend | P0 | Ch4 | Code |
| #12 Implement end-to-end live scan command | MVP | Backend | P0 | Ch5 | Code |
| #13 Build local Minikube and Argo CD lab setup | MVP | Kubernetes | P0 | Ch5 | Documentation |
| #14 Create baseline GitOps application manifests | MVP | Kubernetes | P1 | Ch5 | Code |
| #15 Add controlled drift scenario runner | MVP | Kubernetes | P1 | Ch5 | Test Log |
| #16 Formalize RADAR risk matrix | Policy Engine | Policy | P0 | Ch4 | Documentation |
| #17 Implement RBAC drift classification policies | Policy Engine | Policy | P0 | Ch5 | Code |
| #18 Implement NetworkPolicy drift classification policies | Policy Engine | Policy | P0 | Ch5 | Code |
| #19 Implement workload security context drift policies | Policy Engine | Policy | P0 | Ch5 | Code |
| #20 Implement volume and hostPath drift policies | Policy Engine | Policy | P1 | Ch5 | Code |
| #21 Implement Service exposure drift policies | Policy Engine | Policy | P1 | Ch5 | Code |
| #22 Implement image and secret reference drift policies | Policy Engine | Policy | P1 | Ch5 | Code |
| #23 Add policy regression test suite | Policy Engine | Policy | P0 | Ch5 | Test Log |
| #24 Define evaluation protocol | Evaluation | Evaluation | P0 | Ch5 | Documentation |
| #25 Execute controlled drift experiments | Evaluation | Evaluation | P0 | Ch5 | Test Log |
| #26 Measure detection and classification metrics | Evaluation | Evaluation | P0 | Ch5 | Result Table |
| #27 Prepare evaluation diagrams and result tables | Evaluation | Evaluation | P1 | Ch5 | Diagram |
| #28 Draft Chapter 5 evidence notes | Evaluation | Docs | P1 | Ch5 | Documentation |
| #29 Finalize public release license decision | Public Release | Release | P1 | None | Documentation |
| #30 Prepare public README and installation guide | Public Release | Docs | P1 | Ch6 | Documentation |
| #31 Create demo script and video storyboard | Public Release | Release | P1 | Ch6 | Demo |
| #32 Run public release security audit | Public Release | Release | P0 | None | Test Log |
| #33 Prepare GitHub Wiki structure | Public Release | Docs | P2 | Ch6 | Documentation |
| #34 Prepare portfolio and LinkedIn technical summary | Public Release | Release | P2 | Ch6 | Documentation |

## MVP Dependency

Field-level drift extraction is the next critical MVP dependency. RADAR must not classify live drift as CRITICAL, HIGH, MEDIUM, or LOW from resource-level Argo CD Application status alone. Live risk classification requires field-level evidence such as operation, path, before value, and after value.

## Scope Guardrails

- No dashboard work before MVP completion.
- No Kubernetes controller, CRD, or admission webhook work in the MVP.
- No production deployment manifests.
- No GitHub releases until an end-to-end MVP works.
- No LICENSE file until public release readiness is approved.
- No real credentials, kubeconfigs, cluster URLs, screenshots, or secrets.
