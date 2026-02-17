############################################################
# Gigamon Marketplace VM Module – Variables
############################################################

variable "vm_name" {
  type        = string
  description = "Name of the VM."
}

variable "location" {
  type        = string
  description = "Azure region."
}

variable "resource_group_name" {
  type        = string
  description = "Name of the resource group."
}

variable "subnet_id" {
  type        = string
  description = "Subnet ID to attach the NIC to."
}

variable "vm_size" {
  type        = string
  description = "Azure VM size."
}

variable "admin_username" {
  type        = string
  description = "Admin username for SSH."
}

variable "ssh_public_key" {
  type        = string
  description = "SSH public key for admin access."
}

variable "image_publisher" {
  type        = string
  description = "Marketplace image publisher."
}

variable "image_offer" {
  type        = string
  description = "Marketplace image offer."
}

variable "image_sku" {
  type        = string
  description = "Marketplace image SKU."
}

variable "image_version" {
  type        = string
  description = "Marketplace image version."
}

variable "os_disk_name" {
  type        = string
  description = "Name for the OS disk."
}

variable "pip_name" {
  type        = string
  description = "Name for the public IP resource."
}

variable "nic_name" {
  type        = string
  description = "Name for the network interface."
}

variable "ip_config_name" {
  type        = string
  description = "Name for the IP configuration."
}

variable "role_tag" {
  type        = string
  description = "Value for the Role tag."
}

variable "owner_email" {
  type        = string
  description = "Email for the owner tag."
}

variable "project_tag" {
  type        = string
  description = "Value for the Project tag."
}
