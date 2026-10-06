# Two pipeline identities, both using GitHub OIDC (workload identity federation) - no client secrets.
#
#   plan  : trusted for pull requests and pushes to main. Read-only everywhere.
#   apply : trusted only for jobs running in a GitHub environment (dev/prod), which require
#           manual approval and only accept the main branch. Can change infrastructure.

data "azurerm_subscription" "current" {}

data "github_user" "owner" {
  username = var.github_owner
}

locals {
  github_issuer = "https://token.actions.githubusercontent.com"

  # Immutable subject format (default for repos created after 2026-07-15):
  #   repo:<owner>@<owner_id>/<repo>@<repo_id>:<context>
  # The numeric IDs never change or get reused, so a deleted/renamed repo or account cannot be
  # re-created by someone else to obtain tokens that match these credentials ("subject recycling").
  github_repo = "${var.github_owner}@${data.github_user.owner.id}/${var.github_repository}@${data.github_repository.this.repo_id}"

  plan_subjects = {
    pull-request = "repo:${local.github_repo}:pull_request"
    main         = "repo:${local.github_repo}:ref:refs/heads/main"
  }

  apply_subjects = { for env in var.environments : env => "repo:${local.github_repo}:environment:${env}" }

  # Built-in role ID of "Storage Blob Data Reader" - the only role the apply identity may grant.
  blob_data_reader_role_id = "2a2b9908-6ea1-4ae2-8e65-a410df84e7d1"
}

# --- plan identity ---------------------------------------------------------------------------

resource "azuread_application" "plan" {
  display_name = "gh-${var.github_repository}-tf-plan"
  owners       = [data.azurerm_client_config.current.object_id]
}

resource "azuread_service_principal" "plan" {
  client_id = azuread_application.plan.client_id
  owners    = [data.azurerm_client_config.current.object_id]
}

resource "azuread_application_federated_identity_credential" "plan" {
  for_each = local.plan_subjects

  application_id = azuread_application.plan.id
  display_name   = "github-${each.key}"
  issuer         = local.github_issuer
  subject        = each.value
  audiences      = ["api://AzureADTokenExchange"]
}

resource "azurerm_role_assignment" "plan_reader" {
  scope                = data.azurerm_subscription.current.id
  role_definition_name = "Reader"
  principal_id         = azuread_service_principal.plan.object_id
  principal_type       = "ServicePrincipal"
}

# Read-only on state: PR plans run with -lock=false, so they never need write access.
resource "azurerm_role_assignment" "plan_state" {
  scope                = azurerm_storage_container.state.id
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = azuread_service_principal.plan.object_id
  principal_type       = "ServicePrincipal"
}

# --- apply identity --------------------------------------------------------------------------

resource "azuread_application" "apply" {
  display_name = "gh-${var.github_repository}-tf-apply"
  owners       = [data.azurerm_client_config.current.object_id]
}

resource "azuread_service_principal" "apply" {
  client_id = azuread_application.apply.client_id
  owners    = [data.azurerm_client_config.current.object_id]
}

resource "azuread_application_federated_identity_credential" "apply" {
  for_each = toset(var.environments)

  application_id = azuread_application.apply.id
  display_name   = "github-env-${each.key}"
  issuer         = local.github_issuer
  subject        = "repo:${local.github_repo}:environment:${each.key}"
  audiences      = ["api://AzureADTokenExchange"]
}

resource "azurerm_role_assignment" "apply_contributor" {
  scope                = data.azurerm_subscription.current.id
  role_definition_name = "Contributor"
  principal_id         = azuread_service_principal.apply.object_id
  principal_type       = "ServicePrincipal"
}

# Needed to create the managed identity's role assignment. The ABAC condition limits it to
# creating/deleting "Storage Blob Data Reader" assignments for service principals only, so the
# pipeline cannot escalate its own or anyone else's privileges.
resource "azurerm_role_assignment" "apply_rbac_admin" {
  scope                = data.azurerm_subscription.current.id
  role_definition_name = "Role Based Access Control Administrator"
  principal_id         = azuread_service_principal.apply.object_id
  principal_type       = "ServicePrincipal"
  condition_version    = "2.0"
  condition            = <<-EOT
    (
      (
        !(ActionMatches{'Microsoft.Authorization/roleAssignments/write'})
      )
      OR
      (
        @Request[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAnyValues:GuidEquals {${local.blob_data_reader_role_id}}
        AND
        @Request[Microsoft.Authorization/roleAssignments:PrincipalType] ForAnyOfAnyValues:StringEqualsIgnoreCase {'ServicePrincipal'}
      )
    )
    AND
    (
      (
        !(ActionMatches{'Microsoft.Authorization/roleAssignments/delete'})
      )
      OR
      (
        @Resource[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAnyValues:GuidEquals {${local.blob_data_reader_role_id}}
      )
    )
  EOT
}

resource "azurerm_role_assignment" "apply_state" {
  scope                = azurerm_storage_container.state.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azuread_service_principal.apply.object_id
  principal_type       = "ServicePrincipal"
}
