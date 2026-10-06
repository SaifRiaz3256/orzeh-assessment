variable "name" {
  description = "Globally unique storage account name (3-24 lowercase letters/digits)."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]{3,24}$", var.name))
    error_message = "Storage account name must be 3-24 lowercase letters or digits."
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

variable "replication_type" {
  description = "Replication type. Secure default is geo-zone-redundant; dev may opt down to LRS."
  type        = string
  default     = "GZRS"

  validation {
    condition     = contains(["LRS", "ZRS", "GRS", "GZRS", "RAGRS", "RAGZRS"], var.replication_type)
    error_message = "replication_type must be one of LRS, ZRS, GRS, GZRS, RAGRS, RAGZRS."
  }
}

variable "container_name" {
  description = "Blob container used by the application."
  type        = string
  default     = "appdata"
}

variable "soft_delete_retention_days" {
  description = "Blob and container soft-delete retention."
  type        = number
  default     = 7

  validation {
    condition     = var.soft_delete_retention_days >= 1 && var.soft_delete_retention_days <= 365
    error_message = "Retention must be between 1 and 365 days."
  }
}

variable "private_endpoint_subnet_id" {
  description = "Subnet that hosts the private endpoint."
  type        = string
}

variable "blob_private_dns_zone_id" {
  description = "ID of the privatelink.blob.core.windows.net zone."
  type        = string
}

variable "tags" {
  description = "Tags applied to all resources."
  type        = map(string)
  default     = {}
}
