# [FREE] Enable Organization Policy API on the quota project
resource "google_project_service" "orgpolicy" {
  project                    = var.admin_project_id
  service                    = "orgpolicy.googleapis.com"
  disable_dependent_services = false
  disable_on_destroy         = false
}

locals {
  # CIS GCP Benchmark v2.0 boolean-enforce constraints
  # Applied at org level — inherited by all folders, projects, and resources
  boolean_enforce_policies = toset([
    "compute.requireShieldedVm",               # CIS 4.8  — Shielded VM on all instances
    "compute.requireOsLogin",                  # CIS 4.4  — SSH via IAM, no static keys
    "compute.skipDefaultNetworkCreation",       # CIS 3.1  — no auto-created default VPCs
    "iam.disableServiceAccountKeyCreation",    # CIS 1.4  — no exportable SA keys
    "iam.disableServiceAccountKeyUpload",      # CIS 1.4  — block key upload too
    "iam.automaticIamGrantsForDefaultServiceAccounts", # CIS 1.5 — no auto-Editor on default SAs
    "storage.uniformBucketLevelAccess",        # CIS 5.2  — no ACL-based GCS permissions
    "storage.publicAccessPrevention",          # CIS 5.1  — block public GCS buckets
  ])
}

# [FREE] Org policies carry no direct cost
resource "google_org_policy_policy" "boolean_enforce" {
  for_each   = local.boolean_enforce_policies
  depends_on = [google_project_service.orgpolicy]

  name   = "organizations/${var.org_id}/policies/${each.value}"
  parent = "organizations/${var.org_id}"

  spec {
    rules {
      enforce = "TRUE"
    }
  }
}

# Deny all external IPs on Compute instances — CIS 4.9
# Exception: NAT gateway and load balancers (managed separately, not VM instances)
resource "google_org_policy_policy" "deny_external_ip" {
  depends_on = [google_project_service.orgpolicy]
  name       = "organizations/${var.org_id}/policies/compute.vmExternalIpAccess"
  parent = "organizations/${var.org_id}"

  spec {
    rules {
      deny_all = "TRUE"
    }
  }
}

# Restrict all resource creation to approved regions — prevents data sovereignty issues
# sandbox/ folder policy overrides this for developer experimentation
resource "google_org_policy_policy" "restrict_resource_locations" {
  depends_on = [google_project_service.orgpolicy]
  name       = "organizations/${var.org_id}/policies/gcp.resourceLocations"
  parent = "organizations/${var.org_id}"

  spec {
    rules {
      values {
        allowed_values = var.allowed_locations
      }
    }
  }
}
