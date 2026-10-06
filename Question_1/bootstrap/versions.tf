terraform {
  required_version = ">= 1.9"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.8"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 3.10"
    }
    github = {
      source  = "integrations/github"
      version = "~> 6.13"
    }
  }

  # Bootstrap uses local state: it creates the remote backend everything else uses
  # (chicken-and-egg). Its state can be migrated into that backend afterwards with
  # `terraform init -migrate-state` - see README.
}

provider "azurerm" {
  storage_use_azuread = true

  features {
    storage {
      # Shared keys are disabled and Owner has no data-plane rights, so skip the provider's
      # post-create data-plane checks (queue/static website are not used). Everything here is
      # managed through the management plane.
      data_plane_available = false
    }
  }
}

provider "azuread" {}

# Token comes from the GITHUB_TOKEN environment variable, e.g. `export GITHUB_TOKEN=$(gh auth token)`.
provider "github" {
  owner = var.github_owner
}
