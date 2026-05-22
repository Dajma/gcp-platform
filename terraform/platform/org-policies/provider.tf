provider "google" {
  user_project_override = true
  billing_project       = var.admin_project_id
}
