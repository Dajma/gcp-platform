# Enable Cloud Billing Budget API on admin project before creating budgets
# [FREE] API enablement has no cost
resource "google_project_service" "billing_budgets" {
  project                    = var.admin_project_id
  service                    = "billingbudgets.googleapis.com"
  disable_dependent_services = false
  disable_on_destroy         = false
}

# Org-level spend budget covering ALL projects on this billing account
# Four escalating alerts: 10% ($10), 25% ($25), 50% ($50), 100% ($100)
# [FREE] Budget alerts themselves carry no cost
# LAB: $100 monthly ceiling — raise to $1,000+ for production-scale workloads
resource "google_billing_budget" "org_budget" {
  billing_account = var.billing_account_id
  display_name    = "Platform Lab Monthly Org Budget"

  budget_filter {
    credit_types_treatment = "INCLUDE_ALL_CREDITS"
    calendar_period        = "MONTH"
  }

  amount {
    specified_amount {
      currency_code = "CAD"  # billing account registered in Canada
      units         = tostring(var.budget_amount_usd)
    }
  }

  threshold_rules {
    threshold_percent = 0.1  # $10
    spend_basis       = "CURRENT_SPEND"
  }

  threshold_rules {
    threshold_percent = 0.25  # $25
    spend_basis       = "CURRENT_SPEND"
  }

  threshold_rules {
    threshold_percent = 0.5  # $50
    spend_basis       = "CURRENT_SPEND"
  }

  threshold_rules {
    threshold_percent = 1.0  # $100
    spend_basis       = "CURRENT_SPEND"
  }

  depends_on = [google_project_service.billing_budgets]
}
