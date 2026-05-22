locals {
  # Top-level folders under the GCP Organisation — see ADR-004
  folders = {
    infrastructure  = "infrastructure"
    security        = "security"
    shared_services = "shared-services"
    prod            = "prod"
    nonprod         = "nonprod"
    sandbox         = "sandbox"
  }
}

# [FREE] Folders carry no direct cost
resource "google_folder" "top_level" {
  for_each = local.folders

  display_name = each.value
  parent       = "organizations/${var.org_id}"
}
