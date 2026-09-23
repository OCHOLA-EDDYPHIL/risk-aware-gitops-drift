# Diagrams

These diagrams explain stable RADAR behavior without reproducing the academic report. Each published diagram has an editable Draw.io source and a GitHub-renderable SVG export.

| Diagram | Purpose | Editable source | SVG export |
| --- | --- | --- | --- |
| System architecture | Shows the Git, Argo CD, Kubernetes, RADAR, OPA, and reporting boundaries. | [Draw.io](editable/radar-system-architecture.drawio) | [SVG](exports/radar-system-architecture.svg) |
| Scan pipeline | Follows evidence collection, normalization, atomic comparison, policy evaluation, and reporting. | [Draw.io](editable/radar-scan-pipeline.drawio) | [SVG](exports/radar-scan-pipeline.svg) |
| Drift-record model | Describes the logical JSON report without implying a database. | [Draw.io](editable/radar-drift-record-model.drawio) | [SVG](exports/radar-drift-record-model.svg) |
| Evaluation workflow | Shows the reset-verified, fail-closed sequence used for declared controlled runs. | [Draw.io](editable/radar-evaluation-workflow.drawio) | [SVG](exports/radar-evaluation-workflow.svg) |

## Conventions

- Treat the Draw.io file as the editable source and the SVG as its published export.
- Preserve the off-white canvas, dark outlines, large labels, and restrained RADAR palette.
- Keep execution hosts provider-neutral and keep RADAR read-only in every view.
- Give every SVG a descriptive `title` and `desc`, and use meaningful alternative text when embedding it.
- Do not include credentials, endpoints, host names, private workloads, local paths, or institutional material.
- Do not add PNG or DOT copies unless a separate consumer requires them.

After an edit, validate both XML files, render the SVG at normal documentation width, inspect the result, and run `make docs-check`.

See [Licensing Boundaries](../docs/licensing.md) before redistributing repository documentation or visual assets.
