# Terraform GCS backend configuration — PROD environment
# Copy this file to backend.tfvars and fill in real values.
# backend.tfvars is gitignored — never commit it.
#
# Usage:
#   terraform init -backend-config=../../../terraform/environments/prod/backend.tfvars
#
# PROD RECOMMENDATION: Use a separate state bucket from dev/staging.
# This prevents a compromised nonprod pipeline from accessing prod state.
# In lab, a single bucket with separate prefixes is acceptable.

bucket = "meelass-terraform-state-4740a462"
