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

variable "gigamon_email" {
  type        = string
  description = "Email address used as the owner tag on resources. Useful for resource tracking."
  default     = "pete.connolly@gigamon.com"
}

# -----------------------------------------------------------------------------
# FM Configuration & Credentials
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# FM Configuration & Credentials
# -----------------------------------------------------------------------------

variable "fm_group_name" {
  type        = string
  description = "Monitoring Domain (Group) name to create on FM."
  default     = "Azure-3PO-MD"
}

variable "fm_subgroup_name" {
  type        = string
  description = "Connection (Sub-Group) name to create on FM."
  default     = "Azure-3PO-Connection"
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

# -----------------------------------------------------------------------------
# Optional: FM API token delivery via Azure Key Vault
# -----------------------------------------------------------------------------
# This avoids putting the FM token into Terraform state and avoids manual "push token over SSH".

variable "fm_token_secret_name" {
  type        = string
  description = "Azure Key Vault secret name that will hold the GigaVUE-FM API token (JWT)."
  default     = "gigamon-fm-token"
}
