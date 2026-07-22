# Troubleshooting

## `opa CLI is required`

RADAR delegates Rego evaluation to an `opa` executable on `PATH`. Verify:

```sh
opa version
```

Use the pinned version recorded by the project when reproducing evaluated behavior. Do not replace a missing OPA binary with an unreviewed download in a sensitive environment.

## `server is required` or `token is required`

Fixture scans do not require Argo CD configuration. Live scans require:

```sh
export ARGOCD_SERVER=https://argocd.example.local
export ARGOCD_AUTH_TOKEN='short-lived-read-only-token'
```

Do not paste a real token into an issue, log, screenshot, or command transcript.

## Unauthorized, forbidden, or not found

- `401` usually means the token is missing, expired, or invalid.
- `403` means the account does not have the required Application or project read access.
- `404` can mean the Application name is wrong or deliberately hidden by authorization policy.

Use a least-privilege account. Do not solve an authorization problem by switching to the Argo CD administrator account.

## INFO instead of a security severity

INFO is expected when:

- only resource-level Application status is available;
- desired or live state is missing or malformed;
- field-level comparison cannot be performed safely;
- a field-level change has no configured security rule.

Inspect `change.confidence`, `change.path`, and `evidenceSource`. Do not promote INFO manually without evidence.

## No findings while Argo CD is OutOfSync

Check that the managed-resource response contains stable `predictedLiveState` and `normalizedLiveState`, or their declared fallbacks. A synchronization can change evidence between independent API requests. The research runner addresses this with stable bracketing Application snapshots; the standalone CLI does not claim transactional API collection.

## Git LFS archive is a small text pointer

Retrieve the object:

```sh
git lfs pull
git lfs checkout
```

Then verify it using the adjacent `.sha256` file. Core JSON summaries and metrics do not require LFS.

## Release archive check fails

Run:

```sh
make release-check
```

Packaging requires a clean Go build for Linux amd64 and arm64. Release archives are outputs under `dist/` and are not research evidence.

The packaging script deliberately refuses a non-test release when the code and documentation license files are absent. This is a publication safeguard, not a build error to bypass.

## Lab command rejects the context

This is a safety feature. The research scripts accept only the dedicated `radar-lab` profile and context and additionally verify the API server, CA, and cluster UID. Never bypass the guard or substitute another cluster. Read `k8s-lab/README.md` before operating the lab.
