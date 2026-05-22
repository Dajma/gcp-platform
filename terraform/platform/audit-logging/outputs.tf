output "audit_config_id" {
  description = "ID of the org-level audit config resource"
  value       = google_organization_iam_audit_config.all_services.id
}
