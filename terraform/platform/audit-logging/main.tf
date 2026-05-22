# Org-wide audit logging: ADMIN_READ + DATA_READ + DATA_WRITE for all services
# Required by CIS GCP Benchmark v2.0 sections 2.1, 2.2, 2.3
# [LOW] Data Access logs increase log volume — in lab this is minimal; monitor in prod
resource "google_organization_iam_audit_config" "all_services" {
  org_id  = var.org_id
  service = "allServices"

  audit_log_config {
    log_type = "ADMIN_READ"
  }

  audit_log_config {
    log_type = "DATA_READ"
  }

  audit_log_config {
    log_type = "DATA_WRITE"
  }
}
