# ADR-004: GCP Folder Hierarchy Strategy

**Date:** 2026-05-21
**Status:** Accepted
**Deciders:** Platform Team

---

## Context

GCP's resource hierarchy (`Organization → Folders → Projects → Resources`) is the primary mechanism for:

- Blast-radius isolation (IAM and policy inheritance scope)
- Billing visibility and chargeback attribution
- VPC Service Control perimeter alignment (perimeters require project-level boundaries)
- Logical ownership mapping (one folder = one team's responsibility)

We need a folder structure that supports all of the above while remaining manageable at 11 initial projects and scaling to 50+.

---

## Decision

Six top-level folders directly under the GCP Organisation (`473689265669 / meelass.com`):

```
organizations/473689265669
├── infrastructure/     — VPCs, subnets, DNS, interconnects, NAT, LBs
├── security/           — KMS, SCC, audit sinks, DLP, policy enforcement
├── shared-services/    — CI/CD, Artifact Registry, monitoring, logging hub
├── prod/               — Production workload projects
├── nonprod/            — Staging, dev, and QA workload projects
└── sandbox/            — Unmanaged developer experimentation
```

---

## Folder Mandates

| Folder | Planned projects | IAM group (Phase 2) |
|---|---|---|
| `infrastructure` | `networking-host-prod`, `networking-host-nonprod` | `gcp-network-admins@meelass.com` |
| `security` | `security-tooling`, `kms-prod` | `gcp-security-admins@meelass.com` |
| `shared-services` | `cicd-platform`, `artifact-registry`, `monitoring-prod` | `gcp-devops-admins@meelass.com` |
| `prod` | Future product workload projects | `gcp-prod-operators@meelass.com` |
| `nonprod` | Future staging/dev projects | `gcp-developers@meelass.com` |
| `sandbox` | Individual developer sandboxes | `gcp-developers@meelass.com` |

IAM groups will be created and bound in Phase 2. Folders are empty at Phase 1 — projects added in Phase 5.

---

## Rationale

**Why not flat (all projects directly under org)?**
Flat structure requires per-project IAM bindings. At 50+ projects this is unmanageable and error-prone. A single `setIamPolicy` at the folder level is inherited by all child projects automatically.

**Why not deeper nesting (e.g. `prod/workloads/payments/`)?**
VPC Service Control perimeters cannot span folder hierarchy cleanly. Two levels (org → folder → project) keeps perimeter boundaries aligned with folder boundaries without artificial constraints.

**Why separate `infrastructure` from `shared-services`?**
Network engineers own VPCs, subnets, and routing (`infrastructure`). Platform/DevOps engineers own pipelines, registries, and observability (`shared-services`). Merging them would require overly broad IAM grants to both teams.

**Why a dedicated `security` folder?**
CMEK requires KMS keys to be isolated from the projects they protect — same-project KMS is not meaningful encryption. Security tooling (SCC, audit log sinks, DLP) must not be accessible to workload operators. The `security` folder's IAM binding is narrower than any workload folder.

**Why a `sandbox` folder?**
Sandboxes need selective org policy relaxation (developers need external IPs, may skip Shielded VM during prototyping). Exceptions are applied at `sandbox/` folder level via policy override, not at org level — preserving the strict baseline everywhere else.

---

## Alternatives Considered

| Alternative | Rejected because |
|---|---|
| Single `workloads/` folder for all projects | No blast-radius isolation between prod and nonprod |
| `environments/{prod,staging,dev}/` as top-level | Doesn't separate concern-based ownership (security vs. networking vs. app teams) |
| Projects directly under org (no folders) | Org-level IAM too broad; no environment isolation; no inheritance leverage |
| Deeper nesting (`prod/workloads/`, `prod/data/`) | Complicates VPC Service Controls perimeter alignment; adds management overhead |

---

## Consequences

**Positive:**
- Folder-level IAM bindings scale to 50+ projects with zero per-project IAM changes
- Prod projects cannot be touched by nonprod pipelines (different SA IAM scope per folder)
- VPC Service Controls perimeters cleanly aligned to `prod/` folder projects
- Billing reports can filter by folder for chargeback attribution

**Risks — mitigated:**
- Folders are empty at Phase 1 — projects added in Phase 5 (project factory module)
- Group email addresses (e.g. `gcp-security-admins@meelass.com`) don't exist yet — folder IAM bindings deferred to Phase 2

---

## Related ADRs

- [ADR-002](ADR-002-project-structure.md) — Multi-project topology (defines which projects go in which folders)
- [ADR-001](ADR-001-terraform-state-strategy.md) — GCS per-layer state (each platform layer has isolated state)
