# GitHub side of the pipeline: environments (approval gate + main-only), branch protection,
# and Actions variables. OIDC means there are no secrets to store - the IDs below are not sensitive.

data "github_repository" "this" {
  name = var.github_repository
}

data "github_user" "reviewers" {
  for_each = toset(var.deployment_reviewers)
  username = each.value
}

resource "github_repository_environment" "this" {
  for_each = toset(var.environments)

  repository  = data.github_repository.this.name
  environment = each.value

  # Single-maintainer repo: self-review must be allowed or nobody could approve.
  # With a team, set prevent_self_review = true.
  prevent_self_review = false
  can_admins_bypass   = false

  reviewers {
    users = [for u in data.github_user.reviewers : tonumber(u.id)]
  }

  deployment_branch_policy {
    protected_branches     = false
    custom_branch_policies = true
  }
}

# Only the main branch may deploy to dev or prod.
resource "github_repository_environment_deployment_policy" "main_only" {
  for_each = github_repository_environment.this

  repository     = data.github_repository.this.name
  environment    = each.value.environment
  branch_pattern = "main"
}

# Accepted (Trivy): GIT-0004 commit signing is not configured on the single maintainer's machine; recommended for production.
#trivy:ignore:GIT-0004
resource "github_branch_protection" "main" {
  repository_id = data.github_repository.this.node_id
  pattern       = "main"

  allows_deletions    = false
  allows_force_pushes = false

  # Changes reach main only through a PR whose checks (fmt, validate, scan, plan) pass.
  required_status_checks {
    strict   = true
    contexts = var.required_status_checks
  }

  required_pull_request_reviews {
    # 0 because this is a single-maintainer repo; a team would require >= 1 reviewer.
    required_approving_review_count = 0
    dismiss_stale_reviews           = true
  }
}

resource "github_actions_variable" "azure" {
  for_each = {
    AZURE_TENANT_ID       = data.azurerm_client_config.current.tenant_id
    AZURE_SUBSCRIPTION_ID = data.azurerm_subscription.current.subscription_id
    AZURE_CLIENT_ID_PLAN  = azuread_application.plan.client_id
  }

  repository    = data.github_repository.this.name
  variable_name = each.key
  value         = each.value
}

# The apply identity's client ID only exists inside the protected environments.
resource "github_actions_environment_variable" "apply_client_id" {
  for_each = github_repository_environment.this

  repository    = data.github_repository.this.name
  environment   = each.value.environment
  variable_name = "AZURE_CLIENT_ID_APPLY"
  value         = azuread_application.apply.client_id
}
