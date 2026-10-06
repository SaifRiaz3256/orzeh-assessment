variable "location" {
  description = "Azure region for the state backend."
  type        = string
  default     = "koreacentral"
}

variable "state_resource_group_name" {
  description = "Resource group for Terraform state."
  type        = string
  default     = "rg-orzeh-tfstate"
}

variable "state_storage_account_name" {
  description = "Globally unique storage account name for Terraform state. Must match env/*.backend.hcl."
  type        = string
  default     = "storzehtfstate3256"

  validation {
    condition     = can(regex("^[a-z0-9]{3,24}$", var.state_storage_account_name))
    error_message = "Storage account name must be 3-24 lowercase letters or digits."
  }
}

variable "github_owner" {
  description = "GitHub user or organisation that owns the repository."
  type        = string
  default     = "SaifRiaz3256"
}

variable "github_repository" {
  description = "Repository name (must already exist and have a main branch)."
  type        = string
  default     = "orzeh-assessment"
}

variable "environments" {
  description = "Deployment environments; each gets a GitHub environment and an OIDC subject."
  type        = list(string)
  default     = ["dev", "prod"]
}

variable "deployment_reviewers" {
  description = "GitHub usernames who must approve an apply."
  type        = list(string)
  default     = ["SaifRiaz3256"]
}

variable "required_status_checks" {
  description = "Workflow job names that must pass before a PR can merge into main."
  type        = list(string)
  default     = ["Static checks", "Plan (dev)", "Plan (prod)"]
}

variable "tags" {
  description = "Tags for the state resources."
  type        = map(string)
  default = {
    project    = "orzeh"
    purpose    = "terraform-state"
    managed_by = "terraform"
  }
}
