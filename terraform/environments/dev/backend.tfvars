# Terraform GCS backend configuration — DEV environment
# Copy this file to backend.tfvars and fill in real values.
# backend.tfvars is gitignored — never commit it.
#
# Usage:
#   terraform init -backend-config=../../../terraform/environments/dev/backend.tfvars
#
# The `prefix` value is set per-layer in each layer's own backend config block.
# Only `bucket` is environment-specific here.

bucket = "meelass-terraform-state-4740a462"
