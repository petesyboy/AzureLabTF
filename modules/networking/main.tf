############################################################
# Networking Module – VNets, Subnets, NSGs
############################################################

# Main VNet – hosts all resources: FM, UCT-V controller, vSeries, Tool VM, and Production VMs
resource "azurerm_virtual_network" "visibility_vnet" {
  name                = "visibility-vnet"
  address_space       = ["10.0.0.0/16"]
  location            = var.location
  resource_group_name = var.resource_group_name

  tags = {
    Role    = "visibility"
    owner   = var.owner_email
    Project = var.project_tag
  }
}

# Visibility Subnet – hosts Gigamon components (FM, UCT-V, vSeries) and Tool VM
resource "azurerm_subnet" "visibility_subnet" {
  name                 = "visibility-subnet"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.visibility_vnet.name
  address_prefixes     = ["10.0.1.0/24"]
}

# Production Subnet – hosts application workload VMs (Ubuntu VMs with UCT-V agents)
# Now in the same VNet as visibility subnet to allow vSeries dual-NIC configuration
resource "azurerm_subnet" "production_subnet" {
  name                 = "production-subnet"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.visibility_vnet.name
  address_prefixes     = ["10.0.2.0/24"]
}

############################################################
# Network Security Groups
############################################################

resource "azurerm_network_security_group" "nsg_visibility" {
  name                = "nsg-visibility"
  resource_group_name = var.resource_group_name
  location            = var.location

  # SSH (demo)
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

  # HTTPS (FM UI)
  security_rule {
    name                       = "Allow-HTTPS"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  # HTTP (optional)
  security_rule {
    name                       = "Allow-HTTP"
    priority                   = 120
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  # FM stats from UCT-V Controller (TCP 5671)
  security_rule {
    name                       = "Allow-FM-Stats-5671"
    priority                   = 130
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "5671"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "*"
  }

  # UCT-V Controller control/health (TCP 9900)
  security_rule {
    name                       = "Allow-UCTV-Ctrl-9900"
    priority                   = 140
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "9900"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "*"
  }

  # UCT-V agent registration (TCP 8892)
  security_rule {
    name                       = "Allow-UCTV-Agent-Registration-8892"
    priority                   = 145
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "8892"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  # FM <-> vSeries management API (TCP 8889)
  security_rule {
    name                       = "Allow-vSeries-FM-8889"
    priority                   = 146
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "8889"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  # VXLAN from UCT-V agents to vSeries (UDP 4789)
  security_rule {
    name                       = "Allow-VXLAN-4789"
    priority                   = 150
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Udp"
    source_port_range          = "*"
    destination_port_range     = "4789"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "*"
  }

  # Secure tunnel to vSeries (TCP 11443)
  security_rule {
    name                       = "Allow-SecureTunnel-11443"
    priority                   = 160
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "11443"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "*"
  }

  # ICMP inbound (ping)
  security_rule {
    name                       = "Allow-ICMP-Inbound"
    priority                   = 170
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Icmp"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  # ICMP outbound (ping replies)
  security_rule {
    name                       = "Allow-ICMP-Outbound"
    priority                   = 100
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Icmp"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  # ntopng web interface (TCP 3000)
  security_rule {
    name                       = "Allow-ntopng-3000"
    priority                   = 180
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3000"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  # UCT-V agent control/management (TCP 9902) - allows traffic from prod subnet to visibility
  security_rule {
    name                       = "Allow-UCTV-Agent-9902"
    priority                   = 190
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "9902"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "visibility_nsg_assoc" {
  subnet_id                 = azurerm_subnet.visibility_subnet.id
  network_security_group_id = azurerm_network_security_group.nsg_visibility.id
}

# Apply same NSG to production subnet (both subnets are in the same VNet)
resource "azurerm_subnet_network_security_group_association" "production_nsg_assoc" {
  subnet_id                 = azurerm_subnet.production_subnet.id
  network_security_group_id = azurerm_network_security_group.nsg_visibility.id
}