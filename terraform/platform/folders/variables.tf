variable "org_id" {
  description = "GCP Organisation ID (numeric, no 'organizations/' prefix)"
  type        = string
}

variable "admin_project_id" {
  description = "Admin project ID used for API quota project"
  type        = string
}
