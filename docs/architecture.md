# Architecture

RADAR treats Argo CD as the source of GitOps drift evidence. The Application API supplies application and resource-level sync status. The managed-resources endpoint supplies the normalized desired and live resource objects used for field-level comparison.

The Go CLI is the collector and orchestrator. It validates configuration, calls Argo CD, normalizes data, and writes terminal or JSON reports.

The selected extraction path is `GET /api/v1/applications/{name}/managed-resources`. RADAR compares Argo CD's `predictedLiveState` (normalized desired state) with `normalizedLiveState` (normalized observed state), using `targetState` and `liveState` only as fallbacks. The comparison produces atomic RFC 6902-style add, remove, and replace changes. Kubernetes-owned noise such as status, managed fields, resource versions, generations, UIDs, and timestamps is removed before comparison.

The normalized drift model separates the drift source from policy and reporting. It records the application, project, sync status, health status, affected resource, operation, JSON Pointer path, before/after values, confidence, stable finding ID, observation time, severity, score, reason, recommendation, and evidence source.

When Argo CD returns no usable state or malformed state, RADAR keeps the resource at INFO rather than inventing a security classification. Resource additions and removals are represented as root-path add/remove changes.

OPA/Rego is the policy engine. The scan command evaluates every normalized finding, deterministically selects the highest score, and retains all matched rule IDs. Synthetic scan bundles validate the integrated extraction-to-report path; they are not treated as live-cluster observations.

The risk matrix maps drift scenarios to CRITICAL, HIGH, MEDIUM, LOW, and INFO. INFO is used for resource-level OutOfSync findings where field-level change details are unavailable.

The CLI and JSON report are the primary interfaces for the MVP. A dashboard is explicitly post-MVP.

The controlled environment is a dedicated Minikube profile and Kubernetes context named `radar-lab`. Argo CD has self-heal disabled during observation, exposes its API only through localhost forwarding, and grants RADAR only application/project read access. This lab architecture is implemented as reproducible assets but remains at the implemented evidence tier until the host memory preflight permits a controlled run.
