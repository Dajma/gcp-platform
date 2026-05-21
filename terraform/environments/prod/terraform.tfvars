# PROD environment variables
# Fill in real values after completing bootstrap prerequisites.
# This file IS committed (no secrets). Sensitive values belong in Secret Manager or CI env vars.
#
# PROD NOTE: Prod applies should require explicit approval in CI (see .github/workflows/).
# Never apply prod from a local workstation except in emergencies (break-glass procedure).
#
# REQUIRED — fill these in:
org_id             = ""  # e.g. "123456789012" (numeric string, no "organizations/" prefix)
billing_account_id = ""  # e.g. "XXXXXX-XXXXXX-XXXXXX"
org_domain         = ""  # e.g. "example.com"
primary_region     = ""  # e.g. "us-central1"
admin_project_id   = ""  # e.g. "myorg-terraform-admin"

# Environment identifier — used in resource naming and labels
environment = "prod"

# Standard labels applied to all resources
default_labels = {
  env        = "prod"
  managed-by = "terraform"
  team       = "platform"
  cost-center = "platform"
}
