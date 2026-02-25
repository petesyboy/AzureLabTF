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
  }
}

# Configure the Microsoft Azure Provider.
provider "azurerm" {
  features {}
}

############################################################
# Resource Group
############################################################

# This resource group will contain all the resources deployed by this Terraform configuration.
# The name and location are parameterized for flexibility.
# SSH key generation is defined in keys.tf

resource "azurerm_resource_group" "rg" {
  name     = var.project_name # Example: "connolly-transitory-demo-tf-3po"
  location = var.location     # Example: "uksouth"

  tags = {
    Environment = "demo"
    Owner       = "gigamon-terraform"
    owner       = var.gigamon_email
    Project     = var.project_name # Tag resources with the project name for cost tracking/management.
  }
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

  vm_name             = "fm-612"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  subnet_id           = module.networking.visibility_subnet_id # Deployed in Visibility Subnet
  vm_size             = var.fm_vm_size                         # Configurable VM size (e.g., Standard_D4s_v5)
  admin_username      = var.admin_username
  ssh_public_key      = tls_private_key.lab_key.public_key_openssh
  image_publisher     = var.fm_image_publisher
  image_offer         = var.fm_image_offer
  image_sku           = var.fm_image_sku
  image_version       = var.fm_image_version
  custom_data         = base64encode(local.fm_cloud_init)
  os_disk_name        = "osdisk-fm-612"
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

module "uctv" {
  source = "./modules/gigamon-vm"

  vm_name             = "uctv-controller"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  subnet_id           = module.networking.visibility_subnet_id # Deployed in Visibility Subnet
  vm_size             = var.uctv_vm_size
  admin_username      = var.admin_username
  ssh_public_key      = tls_private_key.lab_key.public_key_openssh
  image_publisher     = var.uctv_image_publisher
  image_offer         = var.uctv_image_offer
  image_sku           = var.uctv_image_sku
  image_version       = var.uctv_image_version
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

  vm_name             = "vseries-node"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  subnet_id           = module.networking.visibility_subnet_id # Deployed in Visibility Subnet
  vm_size             = var.vseries_vm_size
  admin_username      = var.admin_username
  ssh_public_key      = tls_private_key.lab_key.public_key_openssh
  image_publisher     = var.vseries_image_publisher
  image_offer         = var.vseries_image_offer
  image_sku           = var.vseries_image_sku
  image_version       = var.vseries_image_version
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

  vm_name             = "tool-vm"
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

  depends_on = [module.uctv]

  vm_name             = "prod-ubuntu-1"
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

  depends_on = [module.uctv]

  vm_name             = "prod-ubuntu-2"
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
data "azurerm_client_config" "current" {}

resource "local_file" "configure_script" {
  filename = "${path.module}/scripts/configure_lab.py"
  content = templatefile("${path.module}/scripts/configure_lab.py.tftpl", {
    fm_ip             = module.fm.public_ip
    uctv_ip           = module.uctv.private_ip
    uctv_public_ip    = module.uctv.public_ip
    vseries_public_ip = module.vseries.public_ip
    tool_public_ip    = module.tool_vm.public_ip
    prod_ips          = join(",", [module.prod1.public_ip, module.prod2.public_ip])
    key_path          = abspath(local_file.lab_key_pem.filename)
    username          = var.admin_username
    fm_group          = var.fm_group_name
    fm_subgroup       = var.fm_subgroup_name
    subscription_id   = data.azurerm_client_config.current.subscription_id
    tenant_id         = data.azurerm_client_config.current.tenant_id
  })
}
