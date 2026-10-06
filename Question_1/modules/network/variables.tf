variable "name_prefix" {
  description = "Prefix used in resource names, e.g. orzeh-dev."
  type        = string
}

variable "location" {
  description = "Azure region."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group to deploy into."
  type        = string
}

variable "address_space" {
  description = "VNet address space."
  type        = list(string)

  validation {
    condition     = alltrue([for c in var.address_space : can(cidrhost(c, 0))])
    error_message = "Every address_space entry must be a valid CIDR."
  }
}

variable "workload_subnet_prefix" {
  description = "CIDR for the workload subnet."
  type        = string

  validation {
    condition     = can(cidrhost(var.workload_subnet_prefix, 0))
    error_message = "workload_subnet_prefix must be a valid CIDR."
  }
}

variable "private_endpoint_subnet_prefix" {
  description = "CIDR for the private endpoint subnet."
  type        = string

  validation {
    condition     = can(cidrhost(var.private_endpoint_subnet_prefix, 0))
    error_message = "private_endpoint_subnet_prefix must be a valid CIDR."
  }
}

variable "tags" {
  description = "Tags applied to all resources."
  type        = map(string)
  default     = {}
}
