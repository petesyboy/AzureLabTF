################################################################################
# AZURE LAB 6.12 - GIGAMON V SERIES CLOUD TAP DEPLOYMENT
################################################################################
#
# OVERVIEW
# --------
# This Terraform configuration deploys a complete Gigamon V Series cloud-based
# traffic visibility and optimization lab environment in Microsoft Azure. The lab
# demonstrates third-party orchestration and management capabilities using Gigamon's
# GigaVUE-FM platform, rather than relying on native Azure deployment APIs. This
# illustrates how organizations can run independent orchestration and control planes
# in Azure while maintaining centralized, vendor-specific traffic management and
# visibility across cloud infrastructure.
#
# ARCHITECTURE
# -----------
# The deployment creates a complete network topology with the following components:
#
# 1. NETWORKING INFRASTRUCTURE
#    - Two Azure Virtual Networks (VNets)
#    - Visibility VNet (10.0.0.0/16)
#    - Production VNet (10.10.0.0/16)
#    - Two subnets (in separate peered VNets):
#      • Visibility Subnet (10.0.1.0/24) - Gigamon components (FM, UCT-V, vSeries) + Tool VM
#      • Production Subnet (10.10.1.0/24) - Workload VMs and traffic sources/destinations
#    - Network Security Groups (NSGs) with rules for:
#      • SSH access (port 22) from admin machines
#      • HTTP/HTTPS (ports 80, 443) for web interfaces
#      • VXLAN traffic (UDP 4789) for overlay networking
#      • Custom application ports (iperf3, ntopng, etc.)
#
# 2. GIGAMON MANAGEMENT & CONTROL PLANE (Third-Party Orchestration)
#    - GigaVUE-FM 6.12 (Fabric Manager)
#      • Centralized third-party management and orchestration platform
#      • Deployed in Visibility Subnet on configurable VM size
#      • Accessible via HTTPS web interface on public IP
#      • Manages and orchestrates all UCT-V and vSeries components via Gigamon APIs
#      • Note: FM operations are INDEPENDENT of Azure Resource Management APIs
#      • Provides vendor-specific traffic intelligence and control outside Azure's ecosystem
#    
#    - UCT-V Controller (Universal Cloud Tap - Virtual)
#      • Cloud-native tap point controller managed by GigaVUE-FM
#      • Orchestrated through third-party Gigamon control plane (not Azure native)
#      • Manages packet capture and traffic mirroring independent of Azure NSGs
#      • Deployed in Visibility Subnet
#      • Communicates with FM using Gigamon proprietary protocols
#    
#    - vSeries Node
#      • In-line traffic processing node orchestrated by Gigamon
#      • Performs vendor-specific packet inspection, DPI, and optimization
#      • Deployed in Visibility Subnet
#      • Connected to both visibility and production networks for inline visibility
#      • Orchestration is handled by GigaVUE-FM, not Azure service fabric
#
# 3. WORKLOAD & TRAFFIC GENERATION
#    - Tool VM (tool-vm)
#      • Dedicated visibility and analysis node in the Visibility Subnet
#      • Includes: ntopng (network traffic monitoring)
#      • Configured with VXLAN interface (vxlan0, VNI=123, dstport=4789) to receive mirrored traffic
#      • Systemd service ensures VXLAN persistence across reboots
#
#    - Production Ubuntu VM 1 (prod-ubuntu-1)
#      • Complex workload with traffic analytics
#      • Includes: iperf3 (traffic generation)
#      • UCT-V Agent installed for traffic mirroring
#      • Can act as traffic source or destination
#    
#    - Production Ubuntu VM 2 (prod-ubuntu-2)
#      • Lightweight traffic generation workload
#      • Includes: iperf3 for benchmarking and load testing
#      • Used for traffic generation tests and validates vSeries processing
#      • Both prod VMs deployed in Production Subnet with public IPs
#
# DEPLOYMENT DETAILS
# ------------------
# - Region: uksouth (configurable via variables)
# - Provider: Azure Resource Manager (AzureRM) ~> 3.100
# - Terraform Version: >= 1.5.0
# - All resources tagged with project name and owner email for cost tracking
# - SSH key-based authentication for all VMs
# - Resource Group: [project_name]_demo (e.g., "connolly-transitory-demo-tf-3po")
# 
# ORCHESTRATION MODEL
# -------------------
# This lab demonstrates a MULTI-LAYER ORCHESTRATION approach:
# 
# Layer 1 (Infrastructure): Terraform + Azure Resource Manager
#   - Provisions VMs, networking, storage, and IaaS resources using Azure APIs
#   - Provides the underlying cloud compute and network foundation
#
# Layer 2 (Application/Control Plane): GigaVUE-FM + Gigamon V Series
#   - Third-party orchestration platform independent of Azure Resource Manager
#   - Manages traffic visibility, tap points, and packet processing
#   - Communicates via proprietary Gigamon protocols and REST APIs
#   - NOT using Azure Service Fabric, Kubernetes, or ARM templates for control plane
#   - Illustrates how third-party platforms maintain their own orchestration layer
#     on top of Azure infrastructure
#
# OUTPUTS & RESULTS
# -----------------
# After successful deployment, the following outputs are available:
# 
# - fm_public_ip          : Access the GigaVUE-FM web interface (https://<IP>)
# - uctv_public_ip        : UCT-V Controller management/troubleshooting
# - tool_vm_public_ip     : Tool VM access (SSH, ntopng UI on port 3000)
# - vseries_public_ip     : vSeries Node management/troubleshooting
# - prod1_public_ip       : Production Ubuntu VM 1 SSH access
# - prod2_public_ip       : Production Ubuntu VM 2 SSH access
# - fm_token_value        : FM authentication token (required for UCT-V/vSeries setup)
#                           Copy to /etc/gigamon-cloud.conf on UCT-V and vSeries
#
# USE CASES & TESTING
# -------------------
# This lab environment supports:
# 1. Traffic Visibility Testing: Capture and analyze traffic between prod VMs
# 2. Inline Processing: vSeries node can inspect/modify traffic in flight
# 3. Network Telemetry: ntopng on Tool VM provides real-time traffic analytics
# 4. Performance Benchmarking: iperf3 generates various load profiles
# 5. VXLAN Overlay Testing: Test encapsulated traffic over the vSeries
# 6. Cloud-Native Design: Full IaC approach with modular, reusable components
#
# GETTING STARTED
# ---------------
# 1. Review variables.tf for configurable parameters (admin username, VM sizes, etc.)
# 2. Run: terraform plan -out=tfplan
# 3. Review the plan and run: terraform apply tfplan
# 4. Wait for deployment to complete (typically 10–15 minutes)
# 5. Retrieve outputs: terraform output
# 6. Access FM web interface and configure UCT-V/vSeries with the FM token
# 7. SSH into production VMs to generate/monitor traffic
#
################################################################################
# Terraform + AzureRM provider configuration
############################################################

# -----------------------------------------------------------------------------
# Terraform Configuration
# -----------------------------------------------------------------------------
# This block configures the Terraform settings, including the required providers
# and the backend for state storage (local in this case).
resource "null_resource" "deployment_start" {
  triggers = {
    always_run = timestamp()
  }

  provisioner "local-exec" {
    command     = "[int](Get-Date -UFormat %s) | Out-File .start_time -Encoding ascii"
    interpreter = ["PowerShell", "-Command"]
  }
}

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
# ... existing resource group code ...

# -----------------------------------------------------------------------------
# SSH Key Generation
# -----------------------------------------------------------------------------
# Generate a new SSH key pair for this deployment to ensure secure access.
# The private key is saved locally to allow the configuration script to SSH into VMs.

resource "tls_private_key" "lab_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "local_file" "lab_key_pem" {
  content         = tls_private_key.lab_key.private_key_pem
  filename        = "${path.module}/lab_key.pem"
  file_permission = "0600"
}

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
  nic_name            = "nic-vseries"
  ip_config_name      = "ipconfig-vseries"
  role_tag            = "vseries"
  owner_email         = var.gigamon_email
  project_tag         = var.project_name
}

############################################################
# Cloud-init scripts for all VMs
############################################################

# -----------------------------------------------------------------------------
# Cloud-init / User Data Configuration
# -----------------------------------------------------------------------------
# This block defines the scripts that run on VMs upon first boot.
# Includes registration scripts for FM and UCT-V (third-party orchestration),
# and UCT-V agent deployment on production VMs.

locals {
  ubuntu_publisher = "Canonical"
  ubuntu_offer     = var.ubuntu_version == "24.04" ? "ubuntu-24_04-lts" : "ubuntu-22_04-lts"
  ubuntu_sku       = "server"
  ubuntu_version   = "latest"

  # FM Cloud-Init: Minimal init.
  # Configuration is handled post-deployment via API.
  fm_cloud_init = <<-EOF
    #cloud-config
    packages: []
    runcmd:
      - echo "GigaVUE-FM 6.12 initializing..."
  EOF

  # UCT-V Controller Cloud-Init
  # We create the config file with placeholders. The Python script will populate the token.
  uctv_cloud_init = <<-EOF
    #cloud-config
    write_files:
      - path: /etc/gigamon-cloud.conf
        permissions: '0644'
        owner: root:root
        content: |
          Registration:
            groupName: ${var.fm_group_name}
            subGroupName: ${var.fm_subgroup_name}
            token: PLACEHOLDER_TOKEN
            remoteAddress: ${module.fm.public_ip}
            remotePort: 443

    runcmd:
      - echo "UCT-V Controller initialized. Waiting for configuration..."
  EOF

  # vSeries Cloud-Init
  vseries_cloud_init = <<-EOF
    #cloud-config
    write_files:
      - path: /etc/gigamon-cloud.conf
        permissions: '0644'
        owner: root:root
        content: |
          Registration:
            groupName: ${var.fm_group_name}
            subGroupName: ${var.fm_subgroup_name}
            token: PLACEHOLDER_TOKEN
            remoteAddress: ${module.fm.public_ip}
            remotePort: 443

    runcmd:
      - echo "vSeries Node initialized. Waiting for configuration..."
  EOF



  # Tool VM: ntopng + VXLAN termination
  # Deployed in Visibility Subnet
  tool_vm_cloud_init = <<-EOF
    #cloud-config
    package_upgrade: true
    packages:
      - ntopng
      - ufw
      - curl
      - jq

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

    ssh_authorized_keys:
      - ${tls_private_key.lab_key.public_key_openssh}

    runcmd:
      - systemctl daemon-reload
      - systemctl enable vxlan0.service
      - systemctl start vxlan0.service
      - systemctl enable ntopng || true
      - systemctl start ntopng || true
      # Add local firewall exception for VXLAN UDP 4789 (no-op if ufw disabled)
      - ufw allow 4789/udp || true
      # Allow ingress from UCT-V Controller and FM (if needed for tool VM logic)
      - ufw allow from ${module.uctv.private_ip} || true
      - if [ -f /var/run/reboot-required ]; then reboot; fi
  EOF

  # prod1: iperf3 + uctv-agent config placeholder
  # Removed ntopng/vxlan from here
  prod1_cloud_init = <<-EOF
    #cloud-config
    package_upgrade: true
    packages:
      - iperf3
      - curl
      - jq

    write_files:
      # UCT-V Agent Config Placeholder
      - path: /etc/gigamon-cloud.conf
        permissions: '0644'
        owner: root:root
        content: |
          Registration:
            groupName: ${var.fm_group_name}
            subGroupName: ${var.fm_subgroup_name}
            token: PLACEHOLDER_TOKEN
            remoteAddress: ${module.fm.public_ip}
            remotePort: 443

    ssh_authorized_keys:
      - ${tls_private_key.lab_key.public_key_openssh}

    runcmd:
      - echo "Downloading UCT-V agent from Public Blob Storage..."
      - curl -L "https://connollystorageaccount.blob.core.windows.net/uctv-agents/gigamon-gigavue-uctv-6.12.00-amd64.deb" -o /tmp/uctv-agent.deb
      - echo "Installing UCT-V agent..."
      - dpkg -i /tmp/uctv-agent.deb || apt-get install -f -y
      - echo "UCT-V agent installed."
      - if [ -f /var/run/reboot-required ]; then reboot; fi
  EOF

  # prod2: iperf3 + uctv-agent config placeholder
  prod2_cloud_init = <<-EOF
    #cloud-config
    package_upgrade: true
    packages:
      - iperf3
      - curl
      - jq

    write_files:
      # UCT-V Agent Config Placeholder
      - path: /etc/gigamon-cloud.conf
        permissions: '0644'
        owner: root:root
        content: |
          Registration:
            groupName: ${var.fm_group_name}
            subGroupName: ${var.fm_subgroup_name}
            token: PLACEHOLDER_TOKEN
            remoteAddress: ${module.fm.public_ip}
            remotePort: 443

    ssh_authorized_keys:
      - ${tls_private_key.lab_key.public_key_openssh}

    runcmd:
      - echo "Downloading UCT-V agent from Public Blob Storage..."
      - curl -L "https://connollystorageaccount.blob.core.windows.net/uctv-agents/gigamon-gigavue-uctv-6.12.00-amd64.deb" -o /tmp/uctv-agent.deb
      - echo "Installing UCT-V agent..."
      - dpkg -i /tmp/uctv-agent.deb || apt-get install -f -y
      - echo "UCT-V agent installed."
      - if [ -f /var/run/reboot-required ]; then reboot; fi
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

############################################################
# FM token
############################################################

resource "random_string" "fm_token" {
  length  = 32
  special = false
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
