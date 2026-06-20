# Security

RADAR is a security research prototype and must handle credentials carefully.

Do not commit:

- Argo CD tokens.
- Kubernetes kubeconfigs.
- Real cluster URLs.
- Screenshots containing sensitive names, endpoints, tokens, or workloads.
- Real Kubernetes Secrets.
- Private keys or certificates.

Report security problems internally through the private repository issue tracker or direct project supervisor channel. Remove sensitive details from logs before attaching them to issues or pull requests.

All test data must be synthetic. Example domains should use safe placeholder values such as `argocd.example.local` or `registry.example.local`.
