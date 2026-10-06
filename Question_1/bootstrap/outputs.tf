output "state_storage_account_name" {
  description = "State storage account (must match infra/env/*.backend.hcl)."
  value       = azurerm_storage_account.state.name
}

output "plan_client_id" {
  description = "Client ID of the read-only plan identity."
  value       = azuread_application.plan.client_id
}

output "apply_client_id" {
  description = "Client ID of the apply identity."
  value       = azuread_application.apply.client_id
}

output "federated_subjects" {
  description = "OIDC subjects trusted by each identity."
  value = {
    plan  = values(local.plan_subjects)
    apply = values(local.apply_subjects)
  }
}
