############################################################
# Terraform + AzureRM provider configuration
############################################################

# -----------------------------------------------------------------------------
# Terraform Configuration
# -----------------------------------------------------------------------------
# This block configures the Terraform settings, including the required providers
# and the backend for state storage (local in this case).
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
  }
}

# Configure the Microsoft Azure Provider.
provider "azurerm" {
  features {}
}

############################################################
# Resource Group
############################################################

# -----------------------------------------------------------------------------
# Resource Group
# -----------------------------------------------------------------------------
# This resource group will contain all the resources deployed by this Terraform configuration.
# The name and location are parameterized for flexibility.

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
# This module deploys the Virtual Network (VNet), Subnets (Management, Visibility, Production),
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
  ssh_public_key      = var.admin_ssh_public_key
  image_publisher     = var.fm_image_publisher
  image_offer         = var.fm_image_offer
  image_sku           = var.fm_image_sku
  image_version       = var.fm_image_version
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
  ssh_public_key      = var.admin_ssh_public_key
  image_publisher     = var.uctv_image_publisher
  image_offer         = var.uctv_image_offer
  image_sku           = var.uctv_image_sku
  image_version       = var.uctv_image_version
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
  ssh_public_key      = var.admin_ssh_public_key
  image_publisher     = var.vseries_image_publisher
  image_offer         = var.vseries_image_offer
  image_sku           = var.vseries_image_sku
  image_version       = var.vseries_image_version
  os_disk_name        = "osdisk-vseries"
  pip_name            = "pip-vseries"
  nic_name            = "nic-vseries"
  ip_config_name      = "ipconfig-vseries"
  role_tag            = "vseries"
  owner_email         = var.gigamon_email
  project_tag         = var.project_name
}

############################################################
# Cloud-init scripts for production VMs
############################################################

# -----------------------------------------------------------------------------
# Cloud-init / User Data Configuration
# -----------------------------------------------------------------------------
# This block defines the scripts that run on the Linux VMs upon first boot.
# Used for installing packages (iperf3, ntopng) and configuring VXLAN interfaces.

locals {
  ubuntu_publisher = "Canonical"
  ubuntu_offer     = var.ubuntu_version == "24.04" ? "ubuntu-24_04-lts" : "ubuntu-22_04-lts"
  ubuntu_sku       = "server"
  ubuntu_version   = "latest"

  # prod1: Configures a complex workload with ntopng, iperf3, and a VXLAN interface (VNI 123).
  # The VXLAN interface is configured to run persistently via a systemd service.
  prod1_cloud_init = <<-EOF
    #cloud-config
    package_upgrade: true
    packages:
      - ntopng
      - iperf3
      - ufw

    write_files:
      # Script to configure VXLAN interface
      - path: /usr/local/sbin/configure-vxlan0.sh
        permissions: '0755'
        owner: root:root
        content: |
          #!/bin/bash
          set -e

          IFACE="eth0"
          VXLAN_IF="vxlan0"
          VNI="123"
          DSTPORT="4789"

          # Get the IPv4 address on the underlying interface (CIDR)
          UNDERLAY_IP=$(ip -4 addr show dev "$${IFACE}" | awk '/inet / {print $2}' | head -n1)

          echo "Configuring $${VXLAN_IF} on $${IFACE} (IP: $${UNDERLAY_IP}) with VNI $${VNI}, dstport $${DSTPORT}"

          # Create vxlan0 if it doesn't exist
          if ! ip link show "$${VXLAN_IF}" >/dev/null 2>&1; then
            ip link add "$${VXLAN_IF}" type vxlan id "$${VNI}" dev "$${IFACE}" dstport "$${DSTPORT}"
          fi

          # Bring interface up
          ip link set "$${VXLAN_IF}" up

      # Systemd service to ensure VXLAN persists across reboots
      - path: /etc/systemd/system/vxlan0.service
        permissions: '0644'
        owner: root:root
        content: |
          [Unit]
          Description=Configure vxlan0 interface (VNI 123)
          After=network-online.target
          Wants=network-online.target

          [Service]
          Type=oneshot
          ExecStart=/usr/local/sbin/configure-vxlan0.sh
          RemainAfterExit=yes

          [Install]
          WantedBy=multi-user.target

    runcmd:
      - systemctl daemon-reload
      - systemctl enable vxlan0.service
      - systemctl start vxlan0.service
      - systemctl enable ntopng || true
      - systemctl start ntopng || true
      # Add local firewall exception for VXLAN UDP 4789 (no-op if ufw disabled)
      - ufw allow 4789/udp || true
      - if [ -f /var/run/reboot-required ]; then reboot; fi
      # Configure user SSH keys
      - mkdir -p /home/${var.admin_username}/.ssh
      - echo 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILaoWcQZ1D/kVtR6rFNAzm5ruMlhcdkDqhy1f4wfMqs6' >> /home/${var.admin_username}/.ssh/authorized_keys
      - chown -R ${var.admin_username}:${var.admin_username} /home/${var.admin_username}/.ssh
      - chmod 700 /home/${var.admin_username}/.ssh || true
      - chmod 600 /home/${var.admin_username}/.ssh/authorized_keys || true
  EOF

  # prod2: Simpler workload with just iperf3 for traffic generation tests.
  prod2_cloud_init = <<-EOF
    #cloud-config
    package_upgrade: true
    packages:
      - iperf3

    runcmd:
      - if [ -f /var/run/reboot-required ]; then reboot; fi
      - mkdir -p /home/${var.admin_username}/.ssh
      - echo 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILaoWcQZ1D/kVtR6rFNAzm5ruMlhcdkDqhy1f4wfMqs6' >> /home/${var.admin_username}/.ssh/authorized_keys
      - chown -R ${var.admin_username}:${var.admin_username} /home/${var.admin_username}/.ssh
      - chmod 700 /home/${var.admin_username}/.ssh || true
      - chmod 600 /home/${var.admin_username}/.ssh/authorized_keys || true
  EOF
}

############################################################
# Production Ubuntu VMs
############################################################

# -----------------------------------------------------------------------------
# Production Ubuntu Workloads
# -----------------------------------------------------------------------------
# These modules deploy standard Ubuntu VMs to act as traffic sources/destinations.
# They use the cloud-init scripts defined in locals above.

module "prod1" {
  source = "./modules/linux-vm"

  vm_name             = "prod-ubuntu-1"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  subnet_id           = module.networking.production_subnet_id # Deployed in Production Subnet
  vm_size             = var.ubuntu_vm_size
  admin_username      = var.admin_username
  ssh_public_key      = var.admin_ssh_public_key
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

  vm_name             = "prod-ubuntu-2"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  subnet_id           = module.networking.production_subnet_id # Deployed in Production Subnet
  vm_size             = var.ubuntu_vm_size
  admin_username      = var.admin_username
  ssh_public_key      = var.admin_ssh_public_key
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

############################################################
# FM token
############################################################

resource "random_string" "fm_token" {
  length  = 32
  special = false
}
