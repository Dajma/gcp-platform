variable "billing_account_id" {
  description = "GCP Billing Account ID (format: XXXXXX-XXXXXX-XXXXXX, no 'billingAccounts/' prefix)"
  type        = string
}

variable "admin_project_id" {
  description = "Admin project ID where Cloud Billing Budget API is enabled"
  type        = string
}

variable "budget_amount_usd" {
  description = "Monthly budget ceiling in CAD — threshold alerts fire at 10/25/50/100% of this value"
  type        = number
  default     = 100
  # LAB: CAD $100 ceiling (~USD $73) — raise to CAD $1,000+ for production workloads
}
