variable "project" {
  description = "Short project name used in resource names."
  type        = string
  default     = "orzeh"

  validation {
    condition     = can(regex("^[a-z0-9]{2,8}$", var.project))
    error_message = "project must be 2-8 lowercase letters or digits (it is part of the storage account name)."
  }
}

variable "environment" {
  description = "Deployment environment."
  type        = string

  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "environment must be dev or prod."
  }
}

variable "location" {
  description = "Azure region."
  type        = string
  default     = "koreacentral"
}

variable "allowed_locations" {
  description = "Regions permitted by the subscription's 'Allowed resource deployment regions' policy."
  type        = list(string)
  default     = ["koreacentral", "malaysiawest", "polandcentral", "austriaeast", "uaenorth"]
}

variable "address_space" {
  description = "VNet address space."
  type        = list(string)
}

variable "workload_subnet_prefix" {
  description = "CIDR for the workload subnet."
  type        = string
}

variable "private_endpoint_subnet_prefix" {
  description = "CIDR for the private endpoint subnet."
  type        = string
}

variable "storage_replication_type" {
  description = "Storage account replication type (secure default GZRS; dev overrides to LRS)."
  type        = string
  default     = "GZRS"
}

variable "storage_soft_delete_days" {
  description = "Blob and container soft-delete retention in days."
  type        = number
  default     = 30
}

variable "key_vault_soft_delete_days" {
  description = "Key Vault soft-delete retention in days."
  type        = number
  default     = 90
}

variable "key_vault_purge_protection" {
  description = "Enable Key Vault purge protection (irreversible). Secure default; dev opts out."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Extra tags merged onto the default tags."
  type        = map(string)
  default     = {}
}
