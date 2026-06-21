# GitHub Project Board

Project name: RADAR Implementation Board

Project URL: https://github.com/users/OCHOLA-EDDYPHIL/projects/3

## Purpose

Track implementation, policy development, Kubernetes lab work, evaluation, and public release preparation for the RADAR research prototype.

Milestones group work by research phase. The project board visualizes current execution state across those milestones.

## Fields

| Field | Type | Values |
| ----- | ---- | ------ |
| Status | Single select | Backlog, Ready, In Progress, In Review, Blocked, Done |
| Type | Single select | Research, Architecture, Backend, Argo CD, Kubernetes, Policy, CI, Docs, Evaluation, Release |
| Priority | Single select | P0, P1, P2 |
| Chapter Link | Single select | Ch3, Ch4, Ch5, Ch6, None |
| Evidence Needed | Single select | Code, Test Log, Screenshot, Diagram, Result Table, Demo, Documentation, None |

## Status Workflow

| Status | Meaning |
| ------ | ------- |
| Backlog | Work is known but not ready for active implementation. |
| Ready | Work is scoped and ready to start. |
| In Progress | Work is actively being implemented. |
| In Review | Work is in pull request or supervisor review. |
| Blocked | Work is waiting on a dependency, decision, or environment. |
| Done | Work is completed and evidence is available. |

## Issue Metadata Policy

- Use one `type:*` label and one `priority:*` label by default.
- Use milestones for research phase grouping: Foundation, MVP, Policy Engine, Evaluation, Public Release.
- Do not add story points, due dates, effort estimates, or automation until there is a concrete need.
- Keep issue bodies actionable and concise.
- Set Evidence Needed to the main artifact expected from the issue.

## Manual Setup Notes

The project, fields, repository link, and issue item metadata were created through GitHub CLI and GraphQL. If the board view is not already grouped as expected in GitHub's UI, manually create or configure a board view grouped by `Status`.

Manual setup steps:

1. Open the RADAR Implementation Board.
2. Add or select a board layout view.
3. Group the view by `Status`.
4. Keep all newly created issues in `Backlog` until work begins.
