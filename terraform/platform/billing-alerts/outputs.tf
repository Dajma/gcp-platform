output "budget_name" {
  description = "Full resource name of the org-level billing budget"
  value       = google_billing_budget.org_budget.name
}

output "budget_amount_usd" {
  description = "Monthly budget ceiling in USD"
  value       = var.budget_amount_usd
}
