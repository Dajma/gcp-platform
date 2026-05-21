# Org Setup — Prerequisites

This directory documents everything that must exist **before** Phase 1 Terraform can run.

None of this is automated — these are one-time human-run steps that establish the trust anchors the rest of the platform depends on.

## Why Manual?

Bootstrapping a GCP organization with Terraform requires an IAM principal that already has org-level admin permissions. You cannot Terraform your way to those permissions from zero — someone with Cloud Identity / Workspace admin rights must perform these steps manually.

This is consistent with how every serious GCP shop operates. The bootstrap is a controlled, auditable, one-time event, not a CI pipeline job.

## Prerequisites Checklist

See [`prerequisites-checklist.md`](prerequisites-checklist.md) for the step-by-step checklist with exact `gcloud` commands.

## Required Roles for Terraform SA

See [`required-roles.md`](required-roles.md) for the complete list of org-level IAM roles the Terraform super-admin SA requires.

## What You Need Before Starting

| Item | Where to find it | Why it's needed |
|---|---|---|
| GCP Organization ID | `gcloud organizations list` | Required in all TF variables as `org_id` |
| Billing Account ID | `gcloud billing accounts list` | Required to attach billing to new projects |
| Primary region | Your choice | All regional resources default here |
| Admin project ID | Console → Create project (manually) | Hosts the Terraform SA and state bucket |
| Cloud Identity / Workspace domain | Your org domain | Required for group-based IAM in Phase 2 |

## Security Notes

- The super-admin SA has **enormous** blast radius. It can create/destroy projects, modify org policies, and read billing data.
- It should **never** have an exported JSON key. Use `gcloud auth impersonate-service-account` locally and WIF in CI.
- Its usage should be audited — all operations will appear in Cloud Audit Logs under `cloudresourcemanager.googleapis.com`.
- Consider restricting its use to specific IP ranges via `conditions` on the org IAM binding (Phase 2 hardening).
