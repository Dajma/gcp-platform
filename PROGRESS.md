# Platform Build Progress

## Current Phase: 1 — Organization & Folder Hierarchy (COMPLETE)

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
- [x] Verify SA impersonation works locally — confirmed via ADC impersonation
- [x] Install pre-commit hooks: `pre-commit install`

---

## Phase 1 — Organization & Folder Hierarchy

**Status:** COMPLETE
**Started:** 2026-05-21
**Completed:** 2026-05-22

### Checklist

#### Terraform layers applied
- [x] `terraform/platform/folders/` — 6 top-level folders created under org
- [x] `terraform/platform/org-policies/` — 10 CIS GCP Benchmark v2.0 constraints enforced
- [x] `terraform/platform/audit-logging/` — org-wide ADMIN_READ + DATA_READ + DATA_WRITE
- [x] `terraform/platform/billing-alerts/` — CAD $100 budget with 4 threshold alerts
- [x] `docs/decisions/ADR-004-folder-strategy.md`

#### Resources created
- [x] Folder: `infrastructure` — `folders/386767465346`
- [x] Folder: `security` — `folders/509957683122`
- [x] Folder: `shared-services` — `folders/667624449165`
- [x] Folder: `prod` — `folders/442721992513`
- [x] Folder: `nonprod` — `folders/373396933001`
- [x] Folder: `sandbox` — `folders/323037062130`
- [x] Org policy: `compute.requireShieldedVm` (ENFORCE)
- [x] Org policy: `compute.requireOsLogin` (ENFORCE)
- [x] Org policy: `compute.skipDefaultNetworkCreation` (ENFORCE)
- [x] Org policy: `iam.disableServiceAccountKeyCreation` (ENFORCE)
- [x] Org policy: `iam.disableServiceAccountKeyUpload` (ENFORCE)
- [x] Org policy: `iam.automaticIamGrantsForDefaultServiceAccounts` (ENFORCE)
- [x] Org policy: `storage.uniformBucketLevelAccess` (ENFORCE)
- [x] Org policy: `storage.publicAccessPrevention` (ENFORCE)
- [x] Org policy: `compute.vmExternalIpAccess` (DENY ALL)
- [x] Org policy: `gcp.resourceLocations` (ALLOW: us-central1, global)
- [x] Audit logging: `allServices` ADMIN_READ + DATA_READ + DATA_WRITE
- [x] Billing budget: CAD $100 ceiling, alerts at 10/25/50/100%

#### Post-bootstrap IAM fix
- [x] `terraform-org-admin` SA granted `roles/billing.admin` at billing account level
  (org-level billing.admin does not cascade to billingbudgets API)

#### Lessons learned / gotchas
- `orgpolicy.googleapis.com` not enabled by bootstrap script — added `google_project_service` resource
- `gcp.resourceLocations` group value must be `"global"` not `"in:global-locations"` (v2 API)
- `google_billing_budget.billing_account` takes raw ID (no `billingAccounts/` prefix)
- Billing account `01DA3A-863E5F-D24BB4` uses **CAD** currency (not USD)
- `roles/billing.admin` at org level does NOT grant billing budget create permission — must be bound at billing account level
- ADC impersonation must use `gcloud auth application-default login --impersonate-service-account=...`
  (not `gcloud config set auth/impersonate_service_account` which only affects gcloud CLI, not Terraform)

---

## GCP Environment

| Item | Value |
|---|---|
| Organisation | `meelass.com` / `473689265669` |
| Billing account | `01DA3A-863E5F-D24BB4` (CAD currency) |
| Admin project | `meelass-terraform-admin` |
| Terraform SA | `terraform-org-admin@meelass-terraform-admin.iam.gserviceaccount.com` |
| State bucket | `meelass-terraform-state-4740a462` |
| Primary region | `us-central1` |
| Org domain | `meelass.com` |

## Folder IDs

| Folder | ID |
|---|---|
| `infrastructure` | `386767465346` |
| `security` | `509957683122` |
| `shared-services` | `667624449165` |
| `prod` | `442721992513` |
| `nonprod` | `373396933001` |
| `sandbox` | `323037062130` |

---

## Key Decisions Made

| ADR | Decision | Date |
|---|---|---|
| ADR-001 | GCS backend, per-layer state files | 2026-05-20 |
| ADR-002 | Multi-project topology (11 core projects) | 2026-05-20 |
| ADR-003 | Manual bootstrap for state bucket | 2026-05-20 |
| ADR-004 | 6 top-level folders (infrastructure, security, shared-services, prod, nonprod, sandbox) | 2026-05-21 |

---

## Open Questions

- GitHub org/repo name — not yet created (WIF will be configured in Phase 6)

---

## Blockers

None currently.

---

## Phase History

| Phase | Status | Completed |
|---|---|---|
| Phase 0 — Bootstrap & Prerequisites | COMPLETE | 2026-05-21 |
| Phase 1 — Organization & Folder Hierarchy | COMPLETE | 2026-05-22 |

---

## Next Up: Phase 2 — IAM Foundation

**Gate:** Phase 1 is complete. All layers applied and verified.

Phase 2 will cover:
- Group-based IAM strategy — Google Workspace groups mapped to folders
- Break-glass account documentation and alert setup
- Service account strategy document
- No primitive roles org policy (roles/owner, roles/editor blocked)
- IAM audit baseline — `gcloud asset search-all-iam-policies` scan
- ADR: IAM strategy
