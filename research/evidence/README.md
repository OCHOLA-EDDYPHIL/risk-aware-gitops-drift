# RADAR Research Evidence

This directory stores sanitized, immutable evidence collections and their reviewable metadata. Collection identifiers are research-native and describe the research stage or purpose rather than delivery mechanics.

## Evidence tiers

Each record declares one evidence tier: proposed, implemented, fixture-validated, controlled-lab observed, or formally evaluated. A stored fixture or environment manifest does not by itself qualify as controlled-lab observation.

## Collection layout

Each collection uses the following structure:

```text
<collection-id>/
├── assessment-v1.json (optional legacy claim assessment)
├── index.csv
├── archives/
│   ├── <scenario>-run-<number>.tar.zst
│   └── <scenario>-run-<number>.tar.zst.sha256
└── runs/
    └── <scenario>/run-<number>/
        ├── metadata.json
        ├── environment.json
        ├── mutation.json
        ├── argocd-observation.json
        ├── radar-result.json
        └── reset.json
```

The index records the collection identifier, scenario, repetition, run status, evidence tier, expected rule and severity, archive checksum, and archive size. Environment manifests record the immutable RADAR commit, execution provider and region where applicable, machine specification and capacity, and dependency versions. They omit working refs, repository identity, and transient instance identifiers. Completed controlled-lab records also retain the declared mutation, minimal Argo CD observation, RADAR result, and machine-verifiable reset summary.

Schema version 1 qualification records retain the managed-resource response and independently collected RADAR result. Schema version 2 additionally requires the captured Application response and combined scan-input bundle. Schema version 3 is required for new controlled observations. It binds the clean source commit, frozen scanner and policy hashes, environment checksum, stable bracketed Application resource version, exact scan-input checksum, decision and reset operation.

Historical archives, summaries and index rows remain immutable. A collection-level assessment may narrow the claimable tier of a legacy record without rewriting it. The assessment takes precedence when the record is cited or aggregated.

## Preparation and storage

Raw run files remain under the ignored lab evidence directory. Evidence preparation accepts only the declared root-level JSON artifacts. It rejects nested directories, unexpected files, hard links, symbolic links, binaries, control characters, embedded YAML Secrets, private keys and malformed or duplicate-key JSON. It sanitizes supported JSON, validates the complete evidence chain before and after sanitization, creates a deterministic archive, verifies it, enforces a 10 MiB ceiling, generates SHA-256 checksums and the collection index, and confirms that the archive path is eligible for Git LFS.

Only immutable `.tar.zst` archives use Git LFS. Small JSON summaries, CSV indexes, and checksum files remain ordinary Git objects for review. Archives and run summaries are append-only and must not be overwritten. Preparing evidence changes local files only; repository publication and review remain separate delivery actions.

Screenshots, logs, YAML and other undeclared formats are not sanitized automatically and are rejected. Any future format requires a separately documented review procedure before storage rules are expanded.

The evidence-storage decision and its consequences are recorded in [ADR 0002](../../docs/adr/0002-fail-closed-evidence-preparation.md).
