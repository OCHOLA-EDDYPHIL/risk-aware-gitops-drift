# Contributing

RADAR uses an issue-first workflow.

## Branch Naming

- `chore/...` for project maintenance.
- `feat/...` for new functionality.
- `fix/...` for bug fixes.
- `docs/...` for documentation-only work.
- `policy/...` for Rego policy changes.
- `scenario/...` for drift scenario work.

## Workflow

1. Create or link a GitHub issue before starting implementation.
2. Create a branch from `main`.
3. Keep changes scoped to the issue.
4. Open a pull request and use `Closes #issue-number` when the PR completes the issue.
5. Request review before merging.

## Pull Request Requirements

- Explain the change and research relevance.
- Link the issue.
- Run relevant tests.
- Update documentation when behavior, policy, or evaluation scope changes.

## Tests Required

Run:

```sh
make fmt
make test
make build
```

Run `make rego-test` when the OPA CLI is installed. GitHub Actions installs OPA and runs policy tests in CI.

## No Secrets Rule

Do not commit tokens, kubeconfigs, real cluster URLs, screenshots with sensitive data, or real secrets. Use synthetic fixtures only.
