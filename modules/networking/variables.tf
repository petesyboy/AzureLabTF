############################################################
# Networking Module – VNets, Subnets, NSGs
############################################################

variable "resource_group_name" {
  type        = string
  description = "Name of the resource group."
}

variable "location" {
  type        = string
  description = "Azure region."
}

variable "owner_email" {
  type        = string
  description = "Email address for owner tag."
}

variable "project_tag" {
  type        = string
  description = "Value for the Project tag."
}
