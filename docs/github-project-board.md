# GitHub Project Board

Create a GitHub Projects Kanban board with these fields.

| Field | Values |
| ----- | ------ |
| Status | Backlog, Ready, In Progress, In Review, Blocked, Done |
| Type | Research, Architecture, Policy, Backend, Kubernetes, CI, Docs, Evaluation |
| Priority | P0, P1, P2 |
| Milestone | Foundation, MVP, Policy Engine, Evaluation, Public Release |
| Chapter Link | Ch3, Ch4, Ch5, Ch6 |
| Evidence Needed | Screenshot, Test Log, Diagram, Code, Result Table |

## Manual Setup

If GitHub CLI automation is unavailable, create labels matching the Type, Priority, Milestone, Chapter Link, and Evidence Needed fields. Then create milestones named Foundation, MVP, Policy Engine, Evaluation, and Public Release.

The foundation P0 issues are listed in `docs/backlog.md` and can be copied into GitHub issues.
