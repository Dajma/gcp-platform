# ADR-003: Bootstrap Approach

**Status:** Accepted
**Date:** 2026-05-20
**Phase:** 0

## Context

Every Terraform-managed infrastructure platform has a bootstrapping problem:
Terraform needs state storage and an IAM principal with sufficient permissions to
create resources — but both of those things need to be created by _something_.

This is the "who creates the creator?" problem. The approach to solving it
determines how auditable, reproducible, and secure the platform's foundation is.

## Decision

Use a **fully documented manual bootstrap sequence** for the state bucket and super-admin
service account. Everything created manually is:
1. Documented in `bootstrap/` with exact `gcloud` commands
2. Captured in `scripts/bootstrap.sh` as an idempotent script
3. Listed as a prerequisites checklist in `bootstrap/org-setup/prerequisites-checklist.md`

The bootstrap is a one-time human-run event, not a CI/CD job.
After bootstrap, all subsequent resources are Terraform-managed.

The state bucket is the only resource that is not managed by Terraform (the super-admin SA
will be imported into Terraform management in Phase 2; the state bucket has `prevent_destroy = true`
to prevent accidental destruction).

## Rationale

**Why not bootstrap Terraform with Terraform (terraforming the terraformer):**
- Creates a circular dependency — the bootstrap state must live somewhere, leading to infinite regress
- Any approach that claims to solve this either uses local state (unacceptable for teams) or
  has a hidden manual step anyway
- The added complexity is not worth the marginal automation gain for a one-time operation

**Why a script over pure documentation:**
- `scripts/bootstrap.sh` is idempotent — safe to re-run if interrupted
- It validates preconditions (authentication, env vars) before making changes
- It produces auditable output showing what was created
- New team members can run it reliably without interpreting prose documentation

**Why not Terraform Cloud or another bootstrapper:**
- Terraform Cloud is an external SaaS dependency (see ADR-001)
- Google Cloud Deployment Manager could bootstrap GCS + IAM, but adds another tool with its own state problem
- The complexity cost of another tool exceeds the benefit for a one-time operation

## Tradeoffs

- The bootstrap steps are not automatically validated in CI (no `terraform plan` for them)
- Mitigated by: idempotent script + checklist + this ADR documenting expected state
- If bootstrap state drifts (e.g., someone deletes the SA manually), the script detects and
  re-creates — but org-level IAM bindings added manually could be missed
- Mitigation: quarterly IAM access review (see `docs/runbooks/iam-review.md`)

## Alternatives Considered

| Alternative | Why rejected |
|---|---|
| **Use a "bootstrap" Terraform layer with local state, then migrate to GCS** | Works but requires a manual `terraform state push` migration step; no less manual than our approach; local state is an interim risk |
| **Terraform Cloud for bootstrap state** | External SaaS dependency; adds credentials; state leaves GCP trust boundary |
| **Google Cloud Deployment Manager** | Another tool with its own state problem; not widely used; documentation sparse compared to Terraform |
| **Pulumi with local state** | Different toolchain from the rest of the platform; introduces cognitive overhead; same bootstrap problem |
| **Fully manual (no script)** | Undocumented, not reproducible, error-prone; rejected on auditability grounds |

## Consequences

- Phase 0 cannot be completed without a human running `scripts/bootstrap.sh` (or its equivalent manual steps)
- This is acceptable: Phase 0 is a one-time setup event, not a recurring operation
- The bootstrap must be completed and verified before Phase 1 Terraform can initialize
- The state bucket name is an opaque value that must be distributed to all `backend.tfvars` files;
  this is a configuration management concern addressed by the prerequisites checklist
