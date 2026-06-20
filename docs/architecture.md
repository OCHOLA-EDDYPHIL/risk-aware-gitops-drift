# Architecture

RADAR treats Argo CD as the source of GitOps drift evidence. The foundation calls the Argo CD Application API and reads resource-level sync status.

The Go CLI is the collector and orchestrator. It validates configuration, calls Argo CD, normalizes data, and writes terminal or JSON reports.

The normalized drift model separates the drift source from policy and reporting. It records the application, project, sync status, health status, affected resource, change description, severity, score, reason, recommendation, and evidence source.

OPA/Rego is the policy engine. The current policy tests use synthetic field-level fixtures because Argo CD Application status alone does not provide enough information for final risk classification.

The risk matrix maps drift scenarios to CRITICAL, HIGH, MEDIUM, LOW, and INFO. INFO is used for resource-level OutOfSync findings where field-level change details are unavailable.

The CLI and JSON report are the primary interfaces for the MVP. A dashboard is explicitly post-MVP.
