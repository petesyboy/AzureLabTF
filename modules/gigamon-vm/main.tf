############################################################
# Gigamon Marketplace VM Module
# Creates: Public IP, NIC, VM with marketplace plan
############################################################

resource "azurerm_public_ip" "pip" {
  name                = var.pip_name
  resource_group_name = var.resource_group_name
  location            = var.location
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_network_interface" "nic" {
  name                = var.nic_name
  resource_group_name = var.resource_group_name
  location            = var.location

  ip_configuration {
    name                          = var.ip_config_name
    subnet_id                     = var.subnet_id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.pip.id
  }
}

# Optional second NIC for data-plane traffic (e.g. vSeries inline interface)
resource "azurerm_network_interface" "nic2" {
  count               = var.create_secondary_nic ? 1 : 0
  name                = var.secondary_nic_name
  resource_group_name = var.resource_group_name
  location            = var.location

  ip_configuration {
    name                          = "ipconfig-secondary"
    subnet_id                     = var.secondary_subnet_id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_virtual_machine" "vm" {
  name                = var.vm_name
  location            = var.location
  resource_group_name = var.resource_group_name
  network_interface_ids = var.create_secondary_nic ? [
    azurerm_network_interface.nic.id,
    azurerm_network_interface.nic2[0].id
  ] : [azurerm_network_interface.nic.id]
  primary_network_interface_id = azurerm_network_interface.nic.id
  vm_size                      = var.vm_size

  identity {
    type = "SystemAssigned"
  }

  delete_os_disk_on_termination    = true
  delete_data_disks_on_termination = true

  plan {
    name      = var.image_sku
    publisher = var.image_publisher
    product   = var.image_offer
  }

  storage_image_reference {
    publisher = var.image_publisher
    offer     = var.image_offer
    sku       = var.image_sku
    version   = var.image_version
  }

  storage_os_disk {
    name              = var.os_disk_name
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "Premium_LRS"
  }

  os_profile {
    computer_name  = var.vm_name
    admin_username = var.admin_username
    custom_data    = var.custom_data != "" ? var.custom_data : null
  }

  os_profile_linux_config {
    disable_password_authentication = true
    ssh_keys {
      path     = "/home/${var.admin_username}/.ssh/authorized_keys"
      key_data = var.ssh_public_key
    }
  }

  tags = {
    Role    = var.role_tag
    owner   = var.owner_email
    Project = var.project_tag
  }
}

resource "azurerm_dev_test_global_vm_shutdown_schedule" "shutdown" {
  virtual_machine_id = azurerm_virtual_machine.vm.id
  location           = azurerm_virtual_machine.vm.location
  enabled            = true

  daily_recurrence_time = "1900"
  timezone              = "GMT Standard Time"

  notification_settings {
    enabled = false
  }
}
