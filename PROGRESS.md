# Platform Build Progress

## Current Phase: 0 — Bootstrap & Prerequisites (IN PROGRESS)

---

## Phase 0 — Bootstrap & Prerequisites

**Status:** IN PROGRESS
**Started:** 2026-05-20

### Checklist

#### Repository setup (automated)
- [x] Git repository initialized (`main` branch)
- [x] Full directory structure created
- [x] `.gitignore` — TF state, credentials, secrets excluded
- [x] `.pre-commit-config.yaml` — fmt, tflint, checkov, detect-secrets
- [x] `.tflint.hcl` — GCP plugin, naming conventions, documentation rules
- [x] `README.md` — project overview and onboarding
- [x] `CLAUDE.md` — full architectural context
- [x] `PROGRESS.md` — this file
- [x] `bootstrap/terraform-backend/` — GCS backend creation docs and script
- [x] `bootstrap/org-setup/` — prerequisites checklist and required roles
- [x] `bootstrap/billing/` — billing prerequisites
- [x] `scripts/bootstrap.sh` — orchestration script
- [x] `terraform/environments/*/backend.tfvars.template` — state config templates
- [x] `terraform/environments/*/terraform.tfvars` — placeholder variable files
- [x] `docs/decisions/ADR-log.md` — ADR index
- [x] `docs/decisions/ADR-001-terraform-state-strategy.md`
- [x] `docs/decisions/ADR-002-project-structure.md`
- [x] `docs/decisions/ADR-003-bootstrap-approach.md`
- [x] `docs/architecture/system-context.md` — full platform ASCII diagram

#### Human-run manual steps (YOU must complete these)
- [ ] Collect GCP org ID (`gcloud organizations list`)
- [ ] Collect billing account ID (`gcloud billing accounts list`)
- [ ] Choose primary region (e.g. `us-central1`)
- [ ] Enable required APIs (see `bootstrap/org-setup/prerequisites-checklist.md`)
- [ ] Create Terraform state GCS bucket (see `bootstrap/terraform-backend/README.md`)
- [ ] Create super-admin service account (see `bootstrap/org-setup/prerequisites-checklist.md`)
- [ ] Grant org-level roles to super-admin SA (see `bootstrap/org-setup/required-roles.md`)
- [ ] Populate `terraform/environments/dev/terraform.tfvars` with real values
- [ ] Verify SA impersonation works locally
- [ ] Install pre-commit hooks: `pre-commit install`

---

## Key Decisions Made

| ADR | Decision | Date |
|---|---|---|
| ADR-001 | GCS backend, per-layer state files | 2026-05-20 |
| ADR-002 | Multi-project topology (11 core projects) | 2026-05-20 |
| ADR-003 | Manual bootstrap for state bucket | 2026-05-20 |

---

## Open Questions

- GCP Organization ID — not yet collected
- Billing Account ID — not yet collected
- Primary region preference — not yet chosen
- GitHub org/repo name — not yet created (WIF will be configured in Phase 6)
- Custom domain for Cloud Identity / Workspace — needed for group-based IAM in Phase 2

---

## Blockers

None currently.

---

## Phase History

*(phases will be logged here as completed)*

---

## Next Up: Phase 1 — Organization & Folder Hierarchy

**Gate:** Phase 0 is complete when all manual checklist items above are done and SA impersonation is verified working.

Phase 1 will cover:
- Folder structure (prod, nonprod, security, shared-services, infrastructure, sandbox)
- Org-level audit logging (all services, all log types) via `terraform/platform/`
- Foundational org policies (restrictive baseline)
- Billing alerts
- ADR: folder strategy
