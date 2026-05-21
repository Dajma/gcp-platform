# PROD environment variables
# Fill in real values after completing bootstrap prerequisites.
# This file IS committed (no secrets). Sensitive values belong in Secret Manager or CI env vars.
#
# PROD NOTE: Prod applies should require explicit approval in CI (see .github/workflows/).
# Never apply prod from a local workstation except in emergencies (break-glass procedure).
#
# REQUIRED — fill these in:
org_id             = "473689265669"  # e.g. "123456789012" (numeric string, no "organizations/" prefix)
billing_account_id = "01DA3A-863E5F-D24BB4"  # e.g. "XXXXXX-XXXXXX-XXXXXX"
org_domain         = "meelass.com"  # e.g. "example.com"
primary_region     = "us-central1"  # e.g. "us-central1"
admin_project_id   = "meelass-terraform-admin"  # e.g. "myorg-terraform-admin"

# Environment identifier — used in resource naming and labels
environment = "prod"

# Standard labels applied to all resources
default_labels = {
  env        = "prod"
  managed-by = "terraform"
  team       = "platform"
  cost-center = "platform"
}
