# RADAR Research Evidence

This directory stores sanitized, immutable evidence collections and their reviewable metadata. Collection identifiers are research-native and describe the research stage or purpose rather than delivery mechanics.

## Evidence tiers

Each record declares one evidence tier: proposed, implemented, fixture-validated, controlled-lab observed, or formally evaluated. A stored fixture or environment manifest does not by itself qualify as controlled-lab observation.

## Collection layout

Each collection uses the following structure:

```text
<collection-id>/
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

Schema version 1 qualification records retain the managed-resource response and independently collected RADAR result. Schema version 2 additionally requires the captured Application response and the exact combined scan-input bundle supplied to RADAR. These larger records remain inside the immutable archive because they can contain embedded state requiring redaction. Existing version 1 records remain reviewable but must retain the limitation that the classified input was not preserved as one atomic snapshot.

## Preparation and storage

Raw run files remain under the ignored lab evidence directory. The evidence preparation tool rejects unsupported files, binaries, images, and symbolic links; sanitizes supported JSON, YAML, and text records; validates required metadata; creates a deterministic archive; verifies the archive; enforces a 10 MiB ceiling; generates SHA-256 checksums and the collection index; and confirms that the archive path is eligible for Git LFS.

Only immutable `.tar.zst` archives use Git LFS. Small JSON summaries, CSV indexes, and checksum files remain ordinary Git objects for review. Archives and run summaries are append-only and must not be overwritten. Preparing evidence changes local files only; repository publication and review remain separate delivery actions.

Screenshots and other image formats are not sanitized automatically and are rejected. Any future image evidence requires a separately documented manual-review procedure before storage rules are expanded.

The evidence-storage decision and its consequences are recorded in [ADR 0002](../../docs/adr/0002-fail-closed-evidence-preparation.md).
