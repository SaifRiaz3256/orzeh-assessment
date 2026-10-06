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

variable "container_id" {
  description = "Resource Manager ID of the blob container the identity may read."
  type        = string
}

variable "tags" {
  description = "Tags applied to all resources."
  type        = map(string)
  default     = {}
}
