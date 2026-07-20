# Controlled GitOps Baseline

This Kustomize package is the intended state for every RADAR experiment. It contains only synthetic resources in the dedicated `radar-demo` namespace:

- one Deployment and ClusterIP Service;
- a default-deny ingress NetworkPolicy;
- a least-privilege Role, RoleBinding, and ServiceAccount;
- a non-sensitive ConfigMap;
- two explicitly dummy Secrets so a Secret-reference change remains runnable; and
- an `emptyDir` volume that provides an unambiguous control for the hostPath scenario.

Argo CD owns this path. Direct changes are permitted only through the guarded scenario runner and are reset by recreating the synthetic namespace from these exact manifests.
