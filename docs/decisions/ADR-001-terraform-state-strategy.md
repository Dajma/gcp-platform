# ADR-001: Terraform State Strategy

**Status:** Accepted
**Date:** 2026-05-20
**Phase:** 0

## Context

Terraform requires a backend to store state. In a multi-project, multi-team GCP platform,
state management choices have significant consequences for:
- Security (who can read state, which contains sensitive output values)
- Blast radius (can one `terraform destroy` wipe the whole platform?)
- Parallel operations (can teams apply changes simultaneously?)
- Auditability (can we see who changed what, when?)
- Operational resilience (can we recover from corrupted state?)

We are building in a personal GCP lab, but the patterns must be production-grade.

## Decision

Use **GCS backend with one state file per logical layer**, hosted in a dedicated admin project.

Layer → state file mapping:
```
platform/folders          → gs://{bucket}/platform/folders/terraform.tfstate
platform/org-policies     → gs://{bucket}/platform/org-policies/terraform.tfstate
platform/audit-logging    → gs://{bucket}/platform/audit-logging/terraform.tfstate
platform/scc              → gs://{bucket}/platform/scc/terraform.tfstate
platform/billing-alerts   → gs://{bucket}/platform/billing-alerts/terraform.tfstate
networking/hub-prod       → gs://{bucket}/networking/hub-prod/terraform.tfstate
networking/hub-nonprod    → gs://{bucket}/networking/hub-nonprod/terraform.tfstate
security/kms              → gs://{bucket}/security/kms/terraform.tfstate
projects/{name}           → gs://{bucket}/projects/{name}/terraform.tfstate
```

The state bucket itself is created manually (bootstrap) and protected with
`lifecycle { prevent_destroy = true }` once under Terraform management.

## Rationale

**GCS over alternatives:**
- State stays inside the GCP trust boundary — no external SaaS dependency
- GCS natively provides state locking via strong consistency (no DynamoDB table needed)
- IAM-controlled — same identity model as the rest of the platform
- Versioning provides automatic rollback capability
- Stripe, Shopify, Datadog, and similar companies use GCS for GCP platform state

**Per-layer state over monolithic state:**
- A `terraform destroy` in one layer cannot cascade to others
- Teams can run `terraform apply` on different layers simultaneously (no shared lock)
- `terraform plan` on a small layer is fast (seconds, not minutes)
- State reads/writes are narrow — a bug in networking doesn't expose security state
- Aligns with the principle of blast radius isolation that governs the entire project topology

## Tradeoffs

- Cross-layer references must use `terraform_remote_state` data sources or explicit variable passing (adds indirection)
- More `terraform init` invocations when switching layers (acceptable; scripted)
- State bucket is a single point of failure — mitigated by GCS 99.999999999% durability and versioning
- Slightly more cognitive overhead navigating multiple layers (mitigated by clear directory structure)

## Alternatives Considered

| Alternative | Why rejected |
|---|---|
| **Terraform Cloud** | External SaaS dependency; state leaves GCP trust boundary; adds monthly cost; requires another set of credentials |
| **Single monolithic state file** | Catastrophic blast radius; single lock blocks all parallel work; `terraform plan` becomes slow as platform grows |
| **Local state** | Not viable for CI/CD; state lost if laptop wiped; no team collaboration; explicitly prohibited in CLAUDE.md |
| **S3 backend with GCS HMAC** | Unnecessary complexity; S3 backend on GCP requires HMAC keys (more credential surface); GCS native backend is simpler |
| **One state bucket per environment** | More management overhead with no proportional benefit; layer-level isolation already achieves blast radius goals |

## Consequences

- Every Terraform layer must include a `backend "gcs"` block with an explicit `prefix`
- The state bucket name must be propagated to all `backend.tfvars` files
- `terraform_remote_state` data sources must reference exact bucket + prefix paths
- The state bucket must never appear in any Terraform layer's managed resources
  (to avoid the destroy-your-own-backend problem)
- CI/CD must pass `-backend-config` pointing to the appropriate environment's `backend.tfvars`
