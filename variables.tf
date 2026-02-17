# =============================================================================
# Root Variables
# =============================================================================
# This file defines the input variables for the Terraform configuration.
# Variables can be overridden via a `terraform.tfvars` file or `-var` CLI arguments.

# -----------------------------------------------------------------------------
# Region and Project Settings
# -----------------------------------------------------------------------------

variable "location" {
  type        = string
  default     = "uksouth"
  description = "Azure region to deploy resources in. (e.g. uksouth, eastus)"
}

variable "project_name" {
  type        = string
  default     = "connolly-transitory-demo-tf-3po"
  description = "Name of the project/resource group. Used for naming resources and tagging."
}

# -----------------------------------------------------------------------------
# Authentication and Access
# -----------------------------------------------------------------------------

variable "admin_username" {
  type        = string
  default     = "peter"
  description = "Admin username for SSH access to all VMs. Do not use 'admin' or 'root' as they are reserved/blocked by Azure."
}
# Note: For production, consider using Azure Key Vault to manage SSH keys securely.
variable "admin_ssh_public_key" {
  type        = string
  description = "SSH public key used for admin access to all VMs."
  default     = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQC3ox6dPw15tN4XqpgyA7iji2o4VcDFM8tj3gZsTu+d7z8gTGPsYyJ8NmppHDsm6lnUSgdVxCZTzCAXZ2AGNiUTyYMvL6afYLEN0Gb2a1bSpES7nRZZp+aS8dBITNRMqW05AL8NaVoDEKAiU5YNohbHMxwJ4uNKl/P77On1R2W53h1IwjCCSr2YMR4g9CEy7Nkxt9fO+1xPORn0ComEyk6zxrnLN4vaOIaP1B3n0qbDu/6dEzQZ4a1sCkCJsyBKuJ5UZSwVCJEGxi1vmRj+BpInM/ktC91WpLuuDi9dGuGTlX6BFn73bbQTyYfdnPl86AuEHmak7m80N+G45ts/hcs9eEVWRDhdQxF9FjepC4ZG6TWR4YOay10Cn0MM4BCHe/NmePLhsoXKrBplgVwxiutL9DqwzFND4FpJAzIQ9lIzQdhmx47lP24FGuUN7JXl7RBW/RE0YC6rNXkbQqWmchohfgrieVXxhYsZTITfz7eBD/e5qouPo35iksvoSRr/RO0= generated-by-azure"
}

variable "gigamon_email" {
  type        = string
  description = "Email address used as the owner tag on resources. Useful for resource tracking."
  default     = "pete.connolly@gigamon.com"
}

# -----------------------------------------------------------------------------
# General VM Configuration
# -----------------------------------------------------------------------------

variable "ubuntu_version" {
  type        = string
  description = "Ubuntu release to use for VM images. Allowed: \"22.04\" or \"24.04\"."
  default     = "22.04"
}

# -----------------------------------------------------------------------------
# VM Sizes (Compute Resources)
# -----------------------------------------------------------------------------
# Adjust these values to scale vertical compute resources.

variable "fm_vm_size" {
  type    = string
  default = "Standard_D4s_v5" # Recommended minimum for GigaVUE-FM
}

variable "uctv_vm_size" {
  type    = string
  default = "Standard_D4s_v5"
}

variable "vseries_vm_size" {
  type    = string
  default = "Standard_D4s_v5" # Adjust based on throughput requirements
}

variable "ubuntu_vm_size" {
  type    = string
  default = "Standard_B2s" # Burstable series suitable for low-traffic tests
}

# -----------------------------------------------------------------------------
# Gigamon Image References (Azure Marketplace - 6.12)
# -----------------------------------------------------------------------------
# These variables define the specific version of Gigamon software to deploy.
# Ensure the subscription has accepted terms for these specific image URNs.

# GigaVUE-FM
variable "fm_image_publisher" {
  type    = string
  default = "gigamon-inc"
}

variable "fm_image_offer" {
  type    = string
  default = "gigamon-gigavue-cloud-suite-v2"
}

variable "fm_image_sku" {
  type    = string
  default = "gfm-azure-v61200"
}

variable "fm_image_version" {
  type    = string
  default = "6.12.1099"
}

# UCT-V Controller
variable "uctv_image_publisher" {
  type    = string
  default = "gigamon-inc"
}

variable "uctv_image_offer" {
  type    = string
  default = "gigamon-gigavue-cloud-suite-v2"
}

variable "uctv_image_sku" {
  type    = string
  default = "uctv-cntlr-v61200"
}

variable "uctv_image_version" {
  type    = string
  default = "6.12.00"
}

# vSeries Node
variable "vseries_image_publisher" {
  type    = string
  default = "gigamon-inc"
}

variable "vseries_image_offer" {
  type    = string
  default = "gigamon-gigavue-cloud-suite-v2"
}

variable "vseries_image_sku" {
  type    = string
  default = "vseries-node-v61200"
}

variable "vseries_image_version" {
  type    = string
  default = "6.12.00"
}
