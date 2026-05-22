output "enforced_boolean_policies" {
  description = "Set of org policy constraints enforced at the organisation level"
  value       = local.boolean_enforce_policies
}

output "deny_external_ip_policy" {
  description = "Resource name of the vmExternalIpAccess deny-all policy"
  value       = google_org_policy_policy.deny_external_ip.name
}

output "allowed_locations" {
  description = "GCP locations permitted by the resourceLocations org policy"
  value       = var.allowed_locations
}
