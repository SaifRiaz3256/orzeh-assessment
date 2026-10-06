variable "name" {
  description = "Globally unique Key Vault name (3-24 chars)."
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9-]{1,22}[a-zA-Z0-9]$", var.name))
    error_message = "Key Vault name must be 3-24 chars, start with a letter, and contain only letters, digits and hyphens."
  }
}

variable "location" {
  description = "Azure region."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group to deploy into."
  type        = string
}

variable "soft_delete_retention_days" {
  description = "Soft-delete retention (7-90 days)."
  type        = number
  default     = 90

  validation {
    condition     = var.soft_delete_retention_days >= 7 && var.soft_delete_retention_days <= 90
    error_message = "soft_delete_retention_days must be between 7 and 90."
  }
}

variable "purge_protection_enabled" {
  description = "Purge protection. Cannot be disabled once enabled - dev sets false so it can be torn down."
  type        = bool
  default     = true
}

variable "private_endpoint_subnet_id" {
  description = "Subnet that hosts the private endpoint."
  type        = string
}

variable "vault_private_dns_zone_id" {
  description = "ID of the privatelink.vaultcore.azure.net zone."
  type        = string
}

variable "tags" {
  description = "Tags applied to all resources."
  type        = map(string)
  default     = {}
}
