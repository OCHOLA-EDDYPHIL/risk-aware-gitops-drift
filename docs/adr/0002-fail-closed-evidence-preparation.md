# ADR 0002: Fail-Closed Evidence Preparation

Status: Accepted

## Context

Controlled-run artifacts can contain credentials, Kubernetes Secret material, local paths, unsupported binaries, or large records that are unsafe or impractical to review directly in Git. Research evidence must remain reproducible without treating unreviewed raw output as publishable material.

## Decision

Keep raw run output in an ignored workspace and prepare a separate sanitized collection. Accept only the declared root-level JSON artifacts. Redact recognized credentials and embedded JSON Secret data; reject nested directories, unexpected files, hard links, symbolic links, binaries, images, control characters, private keys, embedded YAML Secrets and malformed or duplicate-key JSON.

Preserve the exact captured Application and managed-resource snapshot supplied to RADAR. Schema version 3 binds the source commit, scanner and policy hashes, environment checksum, stable Application resource version, exact scan-input checksum, expected decision and reset operation. Validate cross-artifact identity, chronology, revision and result consistency before and after sanitization. Create deterministic compressed archives, verify them, enforce the declared size ceiling, generate SHA-256 checksums and a reviewable index, and treat run summaries and archives as append-only. Store only immutable compressed archives through selective Git LFS; keep small metadata, result, index, assessment and checksum files as ordinary Git objects. Evidence preparation does not perform repository publication.

## Consequences

Unsupported evidence requires a separate reviewed procedure before it can be retained. Retrieval of complete archives requires Git LFS, while core metadata remains directly reviewable. Corrections produce a new run or collection rather than overwriting an existing evidence record. A durable assessment can narrow a legacy claim without altering the historical archive, and publication remains separate from preparation.
