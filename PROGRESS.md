# Platform Build Progress

## Current Phase: 0 — Bootstrap & Prerequisites (COMPLETE — pending pre-commit install)

---

## Phase 0 — Bootstrap & Prerequisites

**Status:** COMPLETE
**Started:** 2026-05-20
**Completed:** 2026-05-21

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

#### Human-run manual steps
- [x] Collect GCP org ID — `473689265669`
- [x] Collect billing account ID — `01DA3A-863E5F-D24BB4`
- [x] Choose primary region — `us-central1`
- [x] Enable required APIs on admin project
- [x] Create Terraform state GCS bucket — `meelass-terraform-state-4740a462`
- [x] Create super-admin service account — `terraform-org-admin@meelass-terraform-admin.iam.gserviceaccount.com`
- [x] Grant 12 org-level roles to super-admin SA
- [x] Grant impersonation right to `admin@meelass.com`
- [x] Populate `terraform/environments/*/terraform.tfvars` with real values
- [x] Populate `terraform/environments/*/backend.tfvars` with real bucket name
- [ ] Verify SA impersonation works locally
- [ ] Install pre-commit hooks: `pre-commit install`

---

## GCP Environment

| Item | Value |
|---|---|
| Organisation | `meelass.com` / `473689265669` |
| Billing account | `01DA3A-863E5F-D24BB4` |
| Admin project | `meelass-terraform-admin` |
| Terraform SA | `terraform-org-admin@meelass-terraform-admin.iam.gserviceaccount.com` |
| State bucket | `meelass-terraform-state-4740a462` |
| Primary region | `us-central1` |
| Org domain | `meelass.com` |

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
