terraform {
  required_version = ">= 1.5.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.100"
    }
  }
}

provider "azurerm" {
  features {}
}

resource "azurerm_resource_group" "rg" {
  name     = "prod-test-rg"
  location = var.location

  tags = {
    Environment = "prod-test"
    owner       = var.gigamon_email
  }
}

resource "azurerm_virtual_network" "production_vnet" {
  name                = "production-vnet"
  address_space       = ["10.5.0.0/16"]
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_subnet" "production_subnet" {
  name                 = "production-subnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.production_vnet.name
  address_prefixes     = ["10.5.1.0/24"]
}

resource "azurerm_network_security_group" "nsg_production" {
  name                = "nsg-production"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location

  security_rule {
    name                       = "Allow-SSH"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "Allow-UCTV-Agent-9902"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "9902"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "Allow-VXLAN-Prod-4789"
    priority                   = 120
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Udp"
    source_port_range          = "*"
    destination_port_range     = "4789"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "production_nsg_assoc" {
  subnet_id                 = azurerm_subnet.production_subnet.id
  network_security_group_id = azurerm_network_security_group.nsg_production.id
}

resource "azurerm_public_ip" "pip_prod1" {
  name                = "pip-prod1"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_public_ip" "pip_prod2" {
  name                = "pip-prod2"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_network_interface" "nic_prod1" {
  name                = "nic-prod1"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location

  ip_configuration {
    name                          = "ipconfig-prod1"
    subnet_id                     = azurerm_subnet.production_subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.pip_prod1.id
  }
}

resource "azurerm_network_interface" "nic_prod2" {
  name                = "nic-prod2"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location

  ip_configuration {
    name                          = "ipconfig-prod2"
    subnet_id                     = azurerm_subnet.production_subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.pip_prod2.id
  }
}

locals {
  ubuntu_publisher = "Canonical"
  ubuntu_offer     = var.ubuntu_version == "24.04" ? "ubuntu-24_04-lts" : "ubuntu-22_04-lts"
  ubuntu_sku       = "server"
  ubuntu_version   = "latest"

  prod1_cloud_init = <<-EOF
    #cloud-config
    package_upgrade: true
    packages:
      - ntopng
      - iperf3
      - ufw

    write_files:
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

          UNDERLAY_IP=$(ip -4 addr show dev "$${IFACE}" | awk '/inet / {print $2}' | head -n1)

          if ! ip link show "$${VXLAN_IF}" >/dev/null 2>&1; then
            ip link add "$${VXLAN_IF}" type vxlan id "$${VNI}" dev "$${IFACE}" dstport "$${DSTPORT}"
          fi

          ip link set "$${VXLAN_IF}" up

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
      - if [ -f /var/run/reboot-required ]; then reboot; fi
      - systemctl daemon-reload
      - systemctl enable vxlan0.service
      - systemctl start vxlan0.service
      - systemctl enable ntopng || true
      - systemctl start ntopng || true
      - ufw allow 4789/udp || true
      - mkdir -p /home/${var.admin_username}/.ssh
      - echo 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILaoWcQZ1D/kVtR6rFNAzm5ruMlhcdkDqhy1f4wfMqs6' >> /home/${var.admin_username}/.ssh/authorized_keys
      - chown -R ${var.admin_username}:${var.admin_username} /home/${var.admin_username}/.ssh
      - chmod 700 /home/${var.admin_username}/.ssh || true
      - chmod 600 /home/${var.admin_username}/.ssh/authorized_keys || true
  EOF

  prod2_cloud_init = <<-EOF
    #cloud-config
    package_upgrade: true
    packages:
      - iperf3

    runcmd:
      - if [ -f /var/run/reboot-required ]; then reboot; fi
  EOF
}

resource "azurerm_linux_virtual_machine" "prod1" {
  name                  = "prod-ubuntu-1"
  location              = azurerm_resource_group.rg.location
  resource_group_name   = azurerm_resource_group.rg.name
  network_interface_ids = [azurerm_network_interface.nic_prod1.id]
  size                  = var.ubuntu_vm_size

  admin_username                  = var.admin_username
  disable_password_authentication = true

  admin_ssh_key {
    username   = var.admin_username
    public_key = var.admin_ssh_public_key
  }

  custom_data = base64encode(local.prod1_cloud_init)

  source_image_reference {
    publisher = local.ubuntu_publisher
    offer     = local.ubuntu_offer
    sku       = local.ubuntu_sku
    version   = local.ubuntu_version
  }

  os_disk {
    name                 = "osdisk-prod1"
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
  }

  tags = {
    Role  = "production-app"
    owner = var.gigamon_email
  }
}

resource "azurerm_linux_virtual_machine" "prod2" {
  name                  = "prod-ubuntu-2"
  location              = azurerm_resource_group.rg.location
  resource_group_name   = azurerm_resource_group.rg.name
  network_interface_ids = [azurerm_network_interface.nic_prod2.id]
  size                  = var.ubuntu_vm_size

  admin_username                  = var.admin_username
  disable_password_authentication = true

  admin_ssh_key {
    username   = var.admin_username
    public_key = var.admin_ssh_public_key
  }

  custom_data = base64encode(local.prod2_cloud_init)

  source_image_reference {
    publisher = local.ubuntu_publisher
    offer     = local.ubuntu_offer
    sku       = local.ubuntu_sku
    version   = local.ubuntu_version
  }

  os_disk {
    name                 = "osdisk-prod2"
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
  }

  tags = {
    Role  = "production-app"
    owner = var.gigamon_email
  }
}

output "prod1_public_ip" {
  value = azurerm_public_ip.pip_prod1.ip_address
}

output "prod2_public_ip" {
  value = azurerm_public_ip.pip_prod2.ip_address
}
