# ADR 0002: Fail-Closed Evidence Preparation

Status: Accepted

## Context

Controlled-run artifacts can contain credentials, Kubernetes Secret material, local paths, unsupported binaries, or large records that are unsafe or impractical to review directly in Git. Research evidence must remain reproducible without treating unreviewed raw output as publishable material.

## Decision

Keep raw run output in an ignored workspace and prepare a separate sanitized collection. Accept only declared JSON, YAML, text, CSV, checksum, and log formats. Redact recognized credentials and embedded Secret data; reject symbolic links, binaries, images, private keys, unsupported formats, and malformed structured data.

Create deterministic compressed archives, verify them, enforce the declared size ceiling, generate SHA-256 checksums and a reviewable index, and treat run summaries and archives as append-only. Store only immutable compressed archives through selective Git LFS; keep small metadata, result, index, and checksum files as ordinary Git objects. Evidence preparation does not create branches, commit, push, or query delivery state.

## Consequences

Unsupported evidence requires a separate reviewed procedure before it can be retained. Retrieval of complete archives requires Git LFS, while core metadata remains directly reviewable. Corrections produce a new run or collection rather than overwriting an existing evidence record, and publication remains a separate action from preparation.
