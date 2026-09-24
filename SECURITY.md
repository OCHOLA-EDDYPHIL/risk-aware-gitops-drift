# Security Policy

RADAR is a research prototype that reads GitOps drift evidence. It is not a production security control, and its output must not be treated as an authorization or remediation decision.

## Report a Vulnerability Privately

Do not disclose a suspected vulnerability through a public discussion. Use GitHub private vulnerability reporting for this repository. If that facility is unavailable, contact the maintainer privately through the contact method on the maintainer's GitHub profile.

Include only the minimum information needed to reproduce the problem:

- the affected RADAR revision or archive version;
- a concise description and security impact;
- synthetic reproduction steps;
- sanitized logs or fixture data; and
- any known workaround.

Never include credentials, kubeconfigs, private endpoints, private keys, real Kubernetes Secrets, production manifests, or unsanitized cluster evidence. The maintainer will assess the report before any public disclosure. No response-time or remediation-time guarantee is offered.

## Security Boundary

RADAR performs read-only HTTP requests to Argo CD and invokes a local OPA executable. It does not synchronize an Application, mutate Kubernetes, store credentials, route alerts, or remediate drift. A live scan should use a short-lived Argo CD credential limited to the intended Application, project, and managed-resource data.

The `--token` flag exists for compatibility, but `ARGOCD_AUTH_TOKEN` is safer because command arguments can be visible to other processes and shell history. Regardless of delivery method, callers are responsible for protecting the environment and output files.

The research lab has a separate safety boundary: it runs only from the activated
project-local `.radar-env`, accepts only the explicit `radar-lab` profile and
context, uses synthetic workloads, disables Argo CD self-heal during
observation, and verifies reset after each scenario. Its short-lived API token
and browser password are ignored files with mode `0600` below `.radar-env`.
Argo CD is forwarded only to a dynamically allocated `127.0.0.1` port, the
browser uses a read-only account, and setup disables the bootstrap administrator
after provisioning. Do not weaken or bypass those guards, publish the UI, or
include the credentials in screenshots.

## Supported Material

Security fixes are applied to the actively maintained source revision. Historical research archives are immutable evidence and are not rewritten; any correction is published as a new artifact with its own provenance.

Example domains and values must remain synthetic, such as `argocd.example.local`, `registry.example.local`, and dummy Secret data.
