# Demo Script

1. Show the repository structure and explain that RADAR is CLI-first.
2. Run `radar version`.
3. Run `make run-example` to show a sanitized Argo CD Application fixture.
4. Explain that the current Argo CD status path produces INFO findings because field-level diff is not yet available.
5. Run Go tests.
6. Run Rego tests in CI or locally if OPA is installed.
7. Show the backlog item for field-level drift extraction as the next MVP step.
