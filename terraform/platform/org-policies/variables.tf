variable "org_id" {
  description = "GCP Organisation ID (numeric, no 'organizations/' prefix)"
  type        = string
}

variable "admin_project_id" {
  description = "Admin project ID used for API quota project"
  type        = string
}

variable "allowed_locations" {
  description = "GCP location values permitted by the resourceLocations org policy"
  type        = list(string)
  default     = ["in:us-central1-locations", "global"]
}
