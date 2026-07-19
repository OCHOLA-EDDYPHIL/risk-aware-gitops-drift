# ADR 0001: Isolated and Resettable Research Lab

Status: Accepted

## Context

RADAR must observe deliberate Kubernetes configuration drift without operating on unrelated clusters or allowing reconciliation to erase the mutation before evidence is collected. Each observation must start from and return to the same declared synthetic baseline.

## Decision

Use one dedicated Minikube profile and Kubernetes context named `radar-lab`. Require the explicit context on every Kubernetes command, limit workloads to the synthetic `radar-demo` namespace, expose Argo CD only through localhost forwarding, and use least-privilege API and repository credentials. Keep Argo CD self-heal disabled during observation.

Before mutation, verify that the Application is Synced and Healthy, its declared fields match the baseline, and its immutable target commit equals the synchronized revision. Apply one declared mutation, collect the resulting drift, then delete the synthetic namespace, request an explicit Argo CD synchronization at the same revision, and verify every declared baseline resource and field.

## Consequences

Scenario commands fail closed for an unexpected context, mutable or mismatched revision, dirty baseline, failed reset, or missing prerequisite. Deliberate drift remains observable and unrelated clusters and containers remain outside the teardown boundary. The design is a controlled research testbed rather than a production, shared-cluster, or multi-cluster deployment model.
