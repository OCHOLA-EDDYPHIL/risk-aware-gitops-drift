# Architecture

RADAR treats Argo CD as the source of GitOps drift evidence. The Application API supplies application and resource-level sync status. The managed-resources endpoint supplies the normalized desired and live resource objects used for field-level comparison.

The Go CLI is the collector and orchestrator. It validates configuration, calls Argo CD, normalizes data, and writes terminal or JSON reports.

The selected extraction path is `GET /api/v1/applications/{name}/managed-resources`. RADAR compares Argo CD's `predictedLiveState` (normalized desired state) with `normalizedLiveState` (normalized observed state), using `targetState` and `liveState` only as fallbacks. The comparison produces atomic RFC 6902-style add, remove, and replace changes. Kubernetes-owned noise such as status, managed fields, resource versions, generations, UIDs, and timestamps is removed before comparison.

The normalized drift model separates the drift source from policy and reporting. It records the application, project, sync status, health status, affected resource, operation, JSON Pointer path, before/after values, confidence, stable finding ID, observation time, severity, score, reason, recommendation, and evidence source.

When Argo CD returns no usable state or malformed state, RADAR keeps the resource at INFO rather than inventing a security classification. Resource additions and removals are represented as root-path add/remove changes.

OPA/Rego is the policy engine. The scan command evaluates every normalized finding, deterministically selects the highest score, and retains all matched rule IDs. Synthetic scan bundles validate the integrated extraction-to-report path; they are not treated as live-cluster observations.

The risk matrix maps drift scenarios to CRITICAL, HIGH, MEDIUM, LOW, and INFO. INFO is used for resource-level OutOfSync findings where field-level change details are unavailable.

The CLI and JSON report are the primary interfaces. A dashboard is outside the research prototype scope.

The controlled environment is a dedicated Minikube profile and Kubernetes context named `radar-lab`. The context server, CA and cluster UID must match an identity recorded immediately after the profile is created. Argo CD has self-heal disabled during observation, exposes its API through a process-owned, dynamically allocated localhost port, and grants RADAR only application/project read access.

The scenario runner requires a clean source commit equal to the immutable Argo CD revision. It builds the scanner and policy from that commit, records their hashes, applies one synthetic mutation, and accepts a scan bundle only when Application snapshots bracketing managed-resource capture have the same resource version and frozen synchronization state. Reset uses the original revision, requires explicit success from every operation, and verifies the restored declared fields before another run.

The cross-cutting lab and evidence decisions are recorded in [ADR 0001](adr/0001-isolated-resettable-research-lab.md) and [ADR 0002](adr/0002-fail-closed-evidence-preparation.md).
