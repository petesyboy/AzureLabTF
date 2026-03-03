################################################################################
# AZURE LAB 6.12 - GIGAMON V SERIES CLOUD TAP DEPLOYMENT
#
# See README.md for comprehensive documentation including:
# - Architecture overview and design principles
# - Technical specifications
# - Multi-layer orchestration model
# - Deployment outputs and use cases
# - Getting started guide
#
################################################################################
# Terraform + AzureRM provider configuration
############################################################

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.100"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.3"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.9"
    }
  }
}

# Configure the Microsoft Azure Provider.
provider "azurerm" {
  features {
    key_vault {
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = true
    }
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
}

############################################################
# Pre-flight Version Check
############################################################

# This resource provides a brief pause to allow the user to verify the
# Gigamon version before proceeding with the deployment.
resource "null_resource" "version_check" {
  triggers = {
    version = var.gigamon_version
  }
  # This provisioner runs on the machine executing Terraform.
  provisioner "local-exec" {
    command = <<EOT
      echo "======================================================================"
      echo "== WARNING: You are about to deploy Gigamon Cloud Suite version ${var.gigamon_version}. =="
      echo "==                                                                  =="
      echo "== You have 10 seconds to press Ctrl+C to abort the deployment.     =="
      echo "======================================================================"
    EOT
  }
}

resource "time_sleep" "version_check_pause" {
  depends_on      = [null_resource.version_check]
  create_duration = "10s"
  triggers = {
    version = var.gigamon_version
  }
}

############################################################
# Resource Group
############################################################

# This resource group will contain all the resources deployed by this Terraform configuration.
# The name and location are parameterized for flexibility.
# SSH key generation is defined in keys.tf

resource "azurerm_resource_group" "rg" {
  depends_on = [time_sleep.version_check_pause]

  name     = var.project_name # Example: "connolly-transitory-demo-tf-3po"
  location = var.location     # Example: "uksouth"

  tags = {
    Environment    = "demo"
    Owner          = "gigamon-terraform"
    owner          = var.gigamon_email
    Project        = var.project_name # Tag resources with the project name for cost tracking/management.
    DeploymentType = "connolly-demo"
  }
}

############################################################
# Optional: Key Vault for FM Token (no secret in TF state)
############################################################

data "azurerm_client_config" "current" {}

resource "random_string" "kv_suffix" {
  length  = 8
  special = false
  upper   = false
}

resource "azurerm_key_vault" "fm_token_kv" {
  name                = "kv${random_string.kv_suffix.result}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = "standard"

  purge_protection_enabled   = false
  soft_delete_retention_days = 7

  # Use Azure RBAC instead of legacy access policies
  enable_rbac_authorization     = true
  public_network_access_enabled = true

  tags = {
    Environment    = "demo"
    Owner          = "gigamon-terraform"
    owner          = var.gigamon_email
    Project        = var.project_name
    DeploymentType = "connolly-demo"
  }
}

# Allow the Terraform caller to upload/update the token secret.
# Note: role assignments can take a minute or two to propagate.
resource "azurerm_role_assignment" "kv_secrets_officer_current_user" {
  scope                = azurerm_key_vault.fm_token_kv.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}

############################################################
# Networking
############################################################

# -----------------------------------------------------------------------------
# Networking Module
# -----------------------------------------------------------------------------
# This module deploys the Virtual Network (VNet), Subnets (Visibility, Production),
# Network Security Groups (NSGs), and other networking components.
# See ./modules/networking for implementation details.

module "networking" {
  source = "./modules/networking"

  # Pass resource group details so networking resources are created in the correct RG.
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  owner_email         = var.gigamon_email
  project_tag         = var.project_name
}

############################################################
# GigaVUE-FM 6.12
############################################################

# -----------------------------------------------------------------------------
# GigaVUE-FM (Fabric Manager)
# -----------------------------------------------------------------------------
# Deploys the GigaVUE-FM instance, which acts as the management plane for the Gigamon V Series.
# It is deployed into the Visibility subnet.

module "fm" {
  source = "./modules/gigamon-vm"

  vm_name             = "connolly-fm-${replace(var.gigamon_version, ".", "")}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  subnet_id           = module.networking.visibility_subnet_id # Deployed in Visibility Subnet
  vm_size             = var.fm_vm_size                         # Configurable VM size (e.g., Standard_D4s_v5)
  admin_username      = var.admin_username
  ssh_public_key      = tls_private_key.lab_key.public_key_openssh
  image_publisher     = var.gigamon_image_publisher
  image_offer         = var.gigamon_image_offer
  image_sku           = local.fm_image_sku
  image_version       = local.fm_image_version
  custom_data         = base64encode(local.fm_cloud_init)
  os_disk_name        = "osdisk-fm-${replace(var.gigamon_version, ".", "")}"
  pip_name            = "pip-fm" # Public IP for FM access
  nic_name            = "nic-fm"
  ip_config_name      = "ipconfig-fm"
  role_tag            = "fm"
  owner_email         = var.gigamon_email
  project_tag         = var.project_name
}

############################################################
# UCT-V Controller
############################################################

# -----------------------------------------------------------------------------
# UCT-V Controller (Universal Cloud Tap - Virtual)
# -----------------------------------------------------------------------------
# Deploys the UCT-V Controller, which manages tap points in the cloud deployment.

module "uctv_controller" {
  source = "./modules/gigamon-vm"

  vm_name             = "connolly-uctv-controller"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  subnet_id           = module.networking.visibility_subnet_id # Deployed in Visibility Subnet
  vm_size             = var.uctv_vm_size
  admin_username      = var.admin_username
  ssh_public_key      = tls_private_key.lab_key.public_key_openssh
  image_publisher     = var.gigamon_image_publisher
  image_offer         = var.gigamon_image_offer
  image_sku           = local.uctv_image_sku
  image_version       = local.uctv_image_version
  custom_data         = base64encode(local.uctv_cloud_init)
  os_disk_name        = "osdisk-uctv"
  pip_name            = "pip-uctv"
  nic_name            = "nic-uctv"
  ip_config_name      = "ipconfig-uctv"
  role_tag            = "uctv-controller"
  owner_email         = var.gigamon_email
  project_tag         = var.project_name
}

############################################################
# vSeries Node
############################################################

# -----------------------------------------------------------------------------
# vSeries Node
# -----------------------------------------------------------------------------
# Deploys the vSeries Node, which processes and optimizes the traffic.

module "vseries" {
  source = "./modules/gigamon-vm"

  vm_name             = "connolly-vseries-node"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  subnet_id           = module.networking.visibility_subnet_id # Deployed in Visibility Subnet
  vm_size             = var.vseries_vm_size
  admin_username      = var.admin_username
  ssh_public_key      = tls_private_key.lab_key.public_key_openssh
  image_publisher     = var.gigamon_image_publisher
  image_offer         = var.gigamon_image_offer
  image_sku           = local.vseries_image_sku
  image_version       = local.vseries_image_version
  custom_data         = base64encode(local.vseries_cloud_init)
  os_disk_name        = "osdisk-vseries"
  pip_name            = "pip-vseries"
  nic_name            = "nic-vseries-mgmt"
  ip_config_name      = "ipconfig-vseries"
  role_tag            = "vseries"
  owner_email         = var.gigamon_email
  project_tag         = var.project_name

  # Second NIC for data-plane / inline traffic (connects to production subnet)
  secondary_subnet_id  = module.networking.production_subnet_id
  secondary_nic_name   = "nic-vseries-data"
  create_secondary_nic = true
}

# Cloud-init scripts for all VMs are defined in locals.tf

############################################################
# Production Ubuntu VMs
############################################################

# -----------------------------------------------------------------------------
# Production Ubuntu Workloads
# -----------------------------------------------------------------------------
# These modules deploy standard Ubuntu VMs to act as traffic sources/destinations.
# They use the cloud-init scripts defined in locals above.


# -----------------------------------------------------------------------------
# Tool VM (ntopng / VXLAN termination)
# -----------------------------------------------------------------------------
module "tool_vm" {
  source = "./modules/linux-vm"

  vm_name             = "connolly-tool-vm"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  subnet_id           = module.networking.visibility_subnet_id # Deployed in Visibility Subnet
  vm_size             = var.ubuntu_vm_size
  admin_username      = var.admin_username
  ssh_public_key      = tls_private_key.lab_key.public_key_openssh
  image_publisher     = local.ubuntu_publisher
  image_offer         = local.ubuntu_offer
  image_sku           = local.ubuntu_sku
  image_version       = local.ubuntu_version
  custom_data         = base64encode(local.tool_vm_cloud_init)
  os_disk_name        = "osdisk-tool"
  pip_name            = "pip-tool"
  nic_name            = "nic-tool"
  ip_config_name      = "ipconfig-tool"
  role_tag            = "tool-vm"
  owner_email         = var.gigamon_email
  project_tag         = var.project_name
}

module "prod1" {
  source = "./modules/linux-vm"

  depends_on = [module.uctv_controller]

  vm_name             = "connolly-prod-ubuntu-1"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  subnet_id           = module.networking.production_subnet_id # Deployed in Production Subnet
  vm_size             = var.ubuntu_vm_size
  admin_username      = var.admin_username
  ssh_public_key      = tls_private_key.lab_key.public_key_openssh
  image_publisher     = local.ubuntu_publisher
  image_offer         = local.ubuntu_offer
  image_sku           = local.ubuntu_sku
  image_version       = local.ubuntu_version
  custom_data         = base64encode(local.prod1_cloud_init) # Passes the cloud-init script
  os_disk_name        = "osdisk-prod1"
  pip_name            = "pip-prod1"
  nic_name            = "nic-prod1"
  ip_config_name      = "ipconfig-prod1"
  role_tag            = "production-app"
  owner_email         = var.gigamon_email
  project_tag         = var.project_name
}

module "prod2" {
  source = "./modules/linux-vm"

  depends_on = [module.uctv_controller]

  vm_name             = "connolly-prod-ubuntu-2"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  subnet_id           = module.networking.production_subnet_id # Deployed in Production Subnet
  vm_size             = var.ubuntu_vm_size
  admin_username      = var.admin_username
  ssh_public_key      = tls_private_key.lab_key.public_key_openssh
  image_publisher     = local.ubuntu_publisher
  image_offer         = local.ubuntu_offer
  image_sku           = local.ubuntu_sku
  image_version       = local.ubuntu_version
  custom_data         = base64encode(local.prod2_cloud_init) # Passes the cloud-init script
  os_disk_name        = "osdisk-prod2"
  pip_name            = "pip-prod2"
  nic_name            = "nic-prod2"
  ip_config_name      = "ipconfig-prod2"
  role_tag            = "production-app"
  owner_email         = var.gigamon_email
  project_tag         = var.project_name
}


# -----------------------------------------------------------------------------
# Orchestration
# -----------------------------------------------------------------------------
resource "azurerm_role_assignment" "kv_secrets_user_uctv" {
  scope                = azurerm_key_vault.fm_token_kv.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = module.uctv_controller.principal_id
}

resource "azurerm_role_assignment" "kv_secrets_user_vseries" {
  scope                = azurerm_key_vault.fm_token_kv.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = module.vseries.principal_id
}

resource "azurerm_role_assignment" "kv_secrets_user_prod1" {
  scope                = azurerm_key_vault.fm_token_kv.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = module.prod1.principal_id
}

resource "azurerm_role_assignment" "kv_secrets_user_prod2" {
  scope                = azurerm_key_vault.fm_token_kv.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = module.prod2.principal_id
}

resource "local_file" "configure_script" {
  filename = "${path.module}/scripts/configure_lab.py"
  content = templatefile("${path.module}/scripts/configure_lab.py.tftpl", {
    fm_fqdn              = module.fm.public_ip # Used by local script for API calls
    fm_group             = var.fm_group_name
    fm_subgroup          = var.fm_subgroup_name
    key_vault_name       = azurerm_key_vault.fm_token_kv.name
    fm_token_secret_name = var.fm_token_secret_name
    vseries_fqdn         = module.vseries.public_ip # Used for SSH config push
    uctv_controller_fqdn = module.uctv_controller.public_ip # Used for SSH config push
    prod1_fqdn           = module.prod1.public_ip # Used for SSH agent restart
    prod2_fqdn           = module.prod2.public_ip # Used for SSH agent restart
    fm_internal_name     = module.fm.private_ip # Used by agents to find FM
    uctv_internal_name   = module.uctv_controller.private_ip # Used for internal comms
    admin_username       = var.admin_username
  })
}
