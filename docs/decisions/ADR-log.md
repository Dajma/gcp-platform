# Architecture Decision Record Log

Running index of all ADRs for this platform. Add a row every time a new ADR is written.

| ADR | Title | Status | Date | Phase |
|---|---|---|---|---|
| [ADR-001](ADR-001-terraform-state-strategy.md) | Terraform State Strategy | Accepted | 2026-05-20 | 0 |
| [ADR-002](ADR-002-project-structure.md) | Multi-Project Topology | Accepted | 2026-05-20 | 0 |
| [ADR-003](ADR-003-bootstrap-approach.md) | Bootstrap Approach | Accepted | 2026-05-20 | 0 |
| [ADR-004](ADR-004-folder-strategy.md) | GCP Folder Hierarchy Strategy | Accepted | 2026-05-21 | 1 |

---

## ADR Status Definitions

| Status | Meaning |
|---|---|
| **Proposed** | Under discussion, not yet implemented |
| **Accepted** | Decision made, will be or is implemented |
| **Superseded** | Replaced by a later ADR (link to replacement) |
| **Deprecated** | No longer relevant; kept for history |
| **Rejected** | Considered but not adopted; kept to prevent re-litigating |

---

## How to Write an ADR

Copy the template below into `ADR-NNN-short-title.md`. Use the next available number.
File name format: `ADR-NNN-kebab-case-title.md`

```markdown
# ADR-NNN: Title

**Status:** Proposed | Accepted | Superseded | Deprecated | Rejected
**Date:** YYYY-MM-DD
**Phase:** N

## Context

What situation or requirement prompted this decision?
What constraints exist (technical, organizational, cost, security)?

## Decision

What was decided? One clear sentence, then detail.

## Rationale

Why this approach over the alternatives?
What evidence, experience, or principles drove the choice?

## Tradeoffs

What do we give up by making this choice?
What operational burden does this introduce?

## Alternatives Considered

| Alternative | Why rejected |
|---|---|
| Option A | ... |
| Option B | ... |

## Consequences

What changes downstream as a result of this decision?
What must be true for this to work?
```
