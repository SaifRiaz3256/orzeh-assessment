# Credentials are never stored in code. Locally: `az login`. In CI: OIDC via ARM_USE_OIDC,
# ARM_CLIENT_ID, ARM_TENANT_ID and ARM_SUBSCRIPTION_ID environment variables.
provider "azurerm" {
  # Resource providers are registered once by an admin; the read-only plan identity cannot register them.
  resource_provider_registrations = "none"

  # Shared keys are disabled on the storage account, so use Entra ID for storage operations.
  storage_use_azuread = true

  features {
    storage {
      # The account has no public endpoint; skip data-plane calls that would time out from
      # outside the VNet. All storage resources here are managed through the management plane.
      data_plane_available = false
    }

    resource_group {
      prevent_deletion_if_contains_resources = true
    }
  }
}
