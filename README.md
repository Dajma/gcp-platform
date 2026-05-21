# GCP Platform

Production-grade multi-project GCP platform built with Terraform, following the architecture patterns used at companies like Stripe, Shopify, and Datadog.

## Design Philosophy

- **Security first** — controls implemented before workloads, never after
- **Multi-project by design** — blast radius isolation over management convenience
- **Everything as code** — no console clicks in production
- **Auditability over automation** — every change traceable, every decision documented
- **Hub-and-spoke networking** — Shared VPC, private-by-default, no public IPs in prod

## Repository Layout

```
gcp-platform/
├── bootstrap/           # One-time manual setup (org, billing, state bucket)
├── terraform/
│   ├── modules/         # Reusable internal modules (versioned)
│   ├── platform/        # Org-wide resources (folders, org policies, audit logging)
│   ├── networking/      # Shared VPC hub and spokes
│   ├── security/        # KMS, Secret Manager, SCC
│   ├── shared-services/ # Artifact Registry, CI/CD project
│   ├── projects/        # Per-workload project configs
│   └── environments/    # Environment-specific tfvars and backend configs
├── .github/workflows/   # CI/CD pipelines
├── scripts/             # Operational scripts
├── policies/            # OPA/Conftest guardrails
└── docs/                # ADRs, runbooks, architecture diagrams, threat models
```

## Getting Started

**New to this repo?** Start here:

1. Read `CLAUDE.md` — full architectural context and standards
2. Read `PROGRESS.md` — current phase and what's been built
3. Read `docs/decisions/ADR-log.md` — all significant architectural decisions
4. Read `docs/architecture/standards-and-compliance.md` — frameworks and standards applied to this design
5. Read `bootstrap/org-setup/prerequisites-checklist.md` — what must exist before applying Terraform

**Running Terraform locally:**
```bash
# Authenticate using service account impersonation (never use exported keys)
gcloud auth application-default login
gcloud config set auth/impersonate_service_account terraform-org-admin@ADMIN_PROJECT.iam.gserviceaccount.com

# Initialize a layer (example: platform/folders)
cd terraform/platform/folders
terraform init -backend-config=../../../terraform/environments/dev/backend.tfvars
terraform plan -var-file=../../../terraform/environments/dev/terraform.tfvars
```

## Phase Roadmap

| Phase | Name | Status |
|---|---|---|
| 0 | Bootstrap & Prerequisites | In Progress |
| 1 | Organization & Folder Hierarchy | Pending |
| 2 | IAM Foundation | Pending |
| 3 | Networking Foundation | Pending |
| 4 | Security Foundation | Pending |
| 5 | Project Factory | Pending |
| 6 | CI/CD Platform | Pending |
| 7 | GKE Platform | Pending |
| 8 | Observability Stack | Pending |
| 9 | Data & Storage Patterns | Pending |
| 10 | Day-2 & Operational Readiness | Pending |

## Contributing

- All Terraform must pass `fmt`, `validate`, `tflint`, and `checkov` before merge
- Every significant decision needs an ADR in `docs/decisions/`
- Never commit secrets, credentials, or `.tfvars.local` files
- See `CLAUDE.md` for full standards
