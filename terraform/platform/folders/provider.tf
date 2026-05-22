provider "google" {
  # Credentials via ADC. Set impersonation before running:
  #   gcloud config set auth/impersonate_service_account \
  #     terraform-org-admin@meelass-terraform-admin.iam.gserviceaccount.com
  user_project_override = true
  billing_project       = var.admin_project_id
}
