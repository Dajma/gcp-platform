# Billing — Prerequisites and Controls

## Billing Account Setup

A GCP Billing Account must be linked before any project can provision paid resources.
This is done manually in the GCP Console or via `gcloud`.

### Required Before Phase 1

```bash
# List existing billing accounts
gcloud billing accounts list

# Confirm the Terraform SA has billing.admin
gcloud billing accounts get-iam-policy BILLING_ACCOUNT_ID \
  --filter="bindings.members:serviceAccount:terraform-org-admin@ADMIN_PROJECT.iam.gserviceaccount.com"
```

### Link Billing to the Admin Project

```bash
gcloud billing projects link ADMIN_PROJECT_ID \
  --billing-account=BILLING_ACCOUNT_ID
```

---

## Billing Alerts (implemented in Phase 1)

Billing alerts are implemented as Terraform resources in `terraform/platform/billing-alerts/`.
They are listed here for context only.

### Planned alert thresholds (lab environment)

| Threshold | Alert type | Notification channel |
|---|---|---|
| $10/month | Forecasted | Email |
| $25/month | Actual | Email |
| $50/month | Actual | Email + PagerDuty (optional) |
| $100/month | Actual | Email (hard stop investigation trigger) |

These thresholds are intentionally low for a lab environment. For production, multiply by expected
monthly spend and set at 50%, 90%, and 110% of budget.

### Cost center labels

Every project will be labeled with:
```
labels = {
  cost-center  = "platform"   # or "security", "networking", "app-{name}"
  env          = "dev"        # dev | staging | prod
  managed-by   = "terraform"
  team         = "platform"
}
```

This enables per-cost-center billing breakdowns in the Billing Reports UI and in exported
billing data to BigQuery (Phase 8).

---

## FinOps Reminders

- **Cloud NAT logging** is the #1 unexpected cost driver in this architecture. Disable in lab.
  See CLAUDE.md cost controls section.
- **BigQuery log sinks** — always set partition expiration. Without it, log tables grow forever.
- **GKE node pools** — scale to 0 when not in use in lab. Use `gke-node-pool-autoscaler` or
  manually resize.
- Run `gcloud billing accounts describe` monthly in lab to catch unexpected charges early.
