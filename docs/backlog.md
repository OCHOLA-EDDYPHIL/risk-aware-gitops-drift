# Backlog

Issue-ready tasks for GitHub Projects. Suggested metadata fields: Status, Type, Priority, Milestone, Chapter Link, Evidence Needed.

## P0 Foundation

### Set up Go CLI project structure

- Type: Backend
- Priority: P0
- Milestone: Foundation
- Chapter Link: Ch4
- Evidence Needed: Code, Test Log
- Acceptance Criteria: Go module, `cmd/radar`, internal packages, Makefile, and project skeleton exist.

### Implement Argo CD Application API client

- Type: Backend
- Priority: P0
- Milestone: Foundation
- Chapter Link: Ch4
- Evidence Needed: Code, Test Log
- Acceptance Criteria: Client calls `/api/v1/applications/{appName}`, validates URL/token/app, handles status codes, supports context and timeout, and is tested with `httptest`.

### Implement normalized drift model

- Type: Architecture
- Priority: P0
- Milestone: Foundation
- Chapter Link: Ch3
- Evidence Needed: Code, Diagram
- Acceptance Criteria: DriftReport, Finding, ResourceRef, and Change types exist; Argo CD resource-level OutOfSync data maps to INFO findings with resource-status-only confidence.

### Implement OPA/Rego policy scaffold

- Type: Policy
- Priority: P0
- Milestone: Foundation
- Chapter Link: Ch4
- Evidence Needed: Code, Test Log
- Acceptance Criteria: Rego policy and tests classify synthetic drift fixtures for CRITICAL, HIGH, MEDIUM, LOW, and INFO severities.

### Implement terminal and JSON reporting

- Type: Backend
- Priority: P0
- Milestone: Foundation
- Chapter Link: Ch4
- Evidence Needed: Screenshot, Code
- Acceptance Criteria: CLI can emit readable terminal reports and deterministic JSON reports.

### Add CI checks

- Type: CI
- Priority: P0
- Milestone: Foundation
- Chapter Link: Ch4
- Evidence Needed: Test Log
- Acceptance Criteria: GitHub Actions runs gofmt check, Go tests, Go build, installs OPA, and runs Rego tests without cluster credentials.

### Add documentation skeleton

- Type: Docs
- Priority: P0
- Milestone: Foundation
- Chapter Link: Ch3
- Evidence Needed: Code
- Acceptance Criteria: README, CONTRIBUTING, SECURITY, architecture, risk matrix, evaluation plan, backlog, and traceability docs exist.

## P1 MVP

### Add field-level drift extraction from Argo CD API or validated Argo CD-compatible source

- Type: Backend
- Priority: P1
- Milestone: MVP
- Chapter Link: Ch4
- Evidence Needed: Code, Result Table
- Acceptance Criteria: RADAR extracts field-level before/after drift for real Argo CD-managed resources or a validated Argo CD-compatible diff source. This is required before final security severity can be assigned to live drift.

### Implement RBAC escalation scenario

- Type: Policy
- Priority: P1
- Milestone: Policy Engine
- Chapter Link: Ch5
- Evidence Needed: Test Log, Result Table
- Acceptance Criteria: Live or lab drift involving wildcard permissions, cluster-admin binding, secrets access expansion, or privileged subject binding is detected as CRITICAL.

### Implement NetworkPolicy removal scenario

- Type: Policy
- Priority: P1
- Milestone: Policy Engine
- Chapter Link: Ch5
- Evidence Needed: Test Log, Result Table
- Acceptance Criteria: Removal or weakening of NetworkPolicy is detected as HIGH.

### Implement privileged container scenario

- Type: Policy
- Priority: P1
- Milestone: Policy Engine
- Chapter Link: Ch5
- Evidence Needed: Test Log, Result Table
- Acceptance Criteria: Changing `securityContext.privileged` to true is detected as CRITICAL.

### Implement hostPath scenario

- Type: Policy
- Priority: P1
- Milestone: Policy Engine
- Chapter Link: Ch5
- Evidence Needed: Test Log, Result Table
- Acceptance Criteria: Addition of hostPath volumes is detected as HIGH.

### Implement Service exposure scenario

- Type: Policy
- Priority: P1
- Milestone: Policy Engine
- Chapter Link: Ch5
- Evidence Needed: Test Log, Result Table
- Acceptance Criteria: Service type drift to NodePort or LoadBalancer is detected as HIGH.

### Implement unsafe image tag scenario

- Type: Policy
- Priority: P1
- Milestone: Policy Engine
- Chapter Link: Ch5
- Evidence Needed: Test Log, Result Table
- Acceptance Criteria: Drift to `latest` or untrusted image registry is detected as MEDIUM.

### Add local Kubernetes + Argo CD lab manifests

- Type: Kubernetes
- Priority: P1
- Milestone: Evaluation
- Chapter Link: Ch5
- Evidence Needed: Code, Diagram
- Acceptance Criteria: Local lab manifests deploy safe synthetic applications managed by Argo CD.

### Add experiment result logging

- Type: Evaluation
- Priority: P1
- Milestone: Evaluation
- Chapter Link: Ch5
- Evidence Needed: Result Table
- Acceptance Criteria: JSON reports can be stored as experiment logs with scenario name, expected severity, observed severity, and notes.

## P2 Post-MVP

### Minimal dashboard

- Type: Backend
- Priority: P2
- Milestone: Public Release
- Chapter Link: Ch6
- Evidence Needed: Screenshot
- Acceptance Criteria: A minimal dashboard displays existing report data after the CLI MVP is complete.

### SARIF export

- Type: Backend
- Priority: P2
- Milestone: Public Release
- Chapter Link: Ch6
- Evidence Needed: Code
- Acceptance Criteria: RADAR can export findings in SARIF for security tooling integration.

### Slack/webhook alerting

- Type: Backend
- Priority: P2
- Milestone: Public Release
- Chapter Link: Ch6
- Evidence Needed: Code
- Acceptance Criteria: RADAR can send sanitized finding notifications to a configured webhook.

### Kubernetes controller/operator investigation

- Type: Research
- Priority: P2
- Milestone: Public Release
- Chapter Link: Ch6
- Evidence Needed: Diagram
- Acceptance Criteria: Document whether a controller/operator is justified after CLI MVP evaluation.

### Public release packaging

- Type: CI
- Priority: P2
- Milestone: Public Release
- Chapter Link: Ch6
- Evidence Needed: Code
- Acceptance Criteria: Public packaging plan is ready after MVP and license decision.

### Demo video script refinement

- Type: Docs
- Priority: P2
- Milestone: Public Release
- Chapter Link: Ch6
- Evidence Needed: Screenshot
- Acceptance Criteria: Demo script uses sanitized data and reflects current implementation status.
