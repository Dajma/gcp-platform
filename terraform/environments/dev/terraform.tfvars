# DEV environment variables
# Fill in real values after completing bootstrap prerequisites.
# This file IS committed (no secrets). Sensitive values belong in Secret Manager or CI env vars.
#
# REQUIRED — fill these in:
org_id             = ""  # e.g. "123456789012" (numeric string, no "organizations/" prefix)
billing_account_id = ""  # e.g. "XXXXXX-XXXXXX-XXXXXX"
org_domain         = ""  # e.g. "example.com"
primary_region     = ""  # e.g. "us-central1"
admin_project_id   = ""  # e.g. "myorg-terraform-admin"

# Environment identifier — used in resource naming and labels
environment = "dev"

# Standard labels applied to all resources
# Additional resource-specific labels are added per-module
default_labels = {
  env        = "dev"
  managed-by = "terraform"
  team       = "platform"
  cost-center = "platform"
}
