# Terraform GCS backend configuration — STAGING environment
# Copy this file to backend.tfvars and fill in real values.
# backend.tfvars is gitignored — never commit it.
#
# Usage:
#   terraform init -backend-config=../../../terraform/environments/staging/backend.tfvars
#
# In lab environments, staging may share the same state bucket as dev
# using distinct prefix values per layer. In production, use a separate bucket.

bucket = "meelass-terraform-state-4740a462"
