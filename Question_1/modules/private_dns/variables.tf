variable "name_prefix" {
  description = "Prefix used in resource names, e.g. orzeh-dev."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group to deploy into."
  type        = string
}

variable "vnet_id" {
  description = "VNet the zones are linked to."
  type        = string
}

variable "zones" {
  description = "Map of short key => private DNS zone name, e.g. { blob = \"privatelink.blob.core.windows.net\" }."
  type        = map(string)

  validation {
    condition     = alltrue([for z in values(var.zones) : startswith(z, "privatelink.")])
    error_message = "Only privatelink.* zones are expected here."
  }
}

variable "tags" {
  description = "Tags applied to all resources."
  type        = map(string)
  default     = {}
}
