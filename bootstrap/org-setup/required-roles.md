# Terraform Super-Admin SA — Required Org-Level Roles

These roles are granted to `terraform-org-admin@{admin-project}.iam.gserviceaccount.com`
at the **organization level**. Every role here is justified — none are granted for convenience.

## Why Org-Level?

Terraform must be able to create folder and project hierarchies, set org policies, manage billing,
and establish IAM bindings across all projects it creates. These operations require org-level
permissions. There is no narrower scope that enables them.

The SA's blast radius is intentionally large — which is why it **must never have an exported key**
and must only be used via impersonation with full audit logging.

---

## Role Inventory

| Role | Why it's needed | Phase first used |
|---|---|---|
| `roles/resourcemanager.organizationAdmin` | Read org metadata, set org-level IAM | Phase 1 |
| `roles/resourcemanager.folderAdmin` | Create and manage folder hierarchy | Phase 1 |
| `roles/resourcemanager.projectCreator` | Create new GCP projects | Phase 5 |
| `roles/resourcemanager.projectDeleter` | Destroy test projects in sandbox | Phase 5 |
| `roles/billing.admin` | Attach billing accounts to new projects | Phase 5 |
| `roles/iam.organizationRoleAdmin` | Create custom IAM roles at org level | Phase 2 |
| `roles/iam.securityAdmin` | Set IAM policies on projects and resources | Phase 2 |
| `roles/orgpolicy.policyAdmin` | Create and modify org policies | Phase 1 |
| `roles/logging.admin` | Create org-level log sinks | Phase 1 |
| `roles/compute.xpnAdmin` | Configure Shared VPC host/service project attachments | Phase 3 |
| `roles/serviceusage.serviceUsageAdmin` | Enable APIs on new projects | Phase 5 |
| `roles/accesscontextmanager.policyAdmin` | Manage VPC Service Control perimeters | Phase 4 |

---

## What's Intentionally NOT Granted

| Role | Why excluded |
|---|---|
| `roles/owner` | Primitive role — violates least-privilege; never use at org level |
| `roles/editor` | Primitive role — same issue |
| `roles/billing.user` | Read-only billing access not needed for a Terraform SA |
| `roles/iam.workloadIdentityPoolAdmin` | Granted per-project in Phase 6, not org-wide |
| `roles/storage.admin` | SA only needs `objectAdmin` on the state bucket, not org-wide storage control |
| `roles/container.admin` | Granted per-project where GKE is deployed (Phase 7) |

---

## Quarterly Review

This role list should be reviewed quarterly as part of the IAM access review process
(see `docs/runbooks/iam-review.md`). Roles no longer needed in later phases should be revoked.

---

## Anti-Pattern: What Stripe/Shopify/Datadog Do NOT Do

- They do not give engineers org-level owner.
- They do not share a single SA key in a `.env` file in the repo.
- They do not grant `roles/editor` on projects "to make things easier."
- The Terraform SA is a privileged service identity — it is treated like a root account.
  Audit every use. Alert on unexpected use. Rotate impersonation access quarterly.
