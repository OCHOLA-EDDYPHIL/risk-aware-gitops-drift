# Research Traceability

| Research Objective | Implementation Component | Test Scenario | Evaluation Metric | Report Chapter |
| ------------------ | ------------------------ | ------------- | ----------------- | -------------- |
| Identify security-relevant GitOps drift | Argo CD client and normalized drift model | Resource-level OutOfSync | Detection coverage | Ch3, Ch4 |
| Classify drift by security risk | OPA/Rego policy engine | RBAC, NetworkPolicy, privileged container, hostPath, Service exposure, image tag, Secret reference, metadata | Expected versus observed severity | Ch4, Ch5 |
| Produce explainable evidence | Terminal and JSON reports | All scenarios | Explanation quality and reproducibility | Ch5 |
| Evaluate against raw Argo CD reporting | Evaluation plan and experiment logs | Full MVP scenario set | Added context, false positives, false negatives, time-to-detect | Ch5 |
| Prepare responsible release | Security docs and release checklist | Public release readiness | Secret hygiene and documentation completeness | Post-project release |
