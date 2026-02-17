############################################################
# Networking Module – VNets, Subnets, NSGs
############################################################

# Visibility VNet – hosts FM, UCT-V controller, vSeries
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

resource "azurerm_subnet" "visibility_subnet" {
  name                 = "visibility-subnet"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.visibility_vnet.name
  address_prefixes     = ["10.0.1.0/24"]
}

# Production VNet – Ubuntu application VMs (for UCT-V agents)
resource "azurerm_virtual_network" "production_vnet" {
  name                = "production-vnet"
  address_space       = ["10.5.0.0/16"]
  location            = var.location
  resource_group_name = var.resource_group_name

  tags = {
    Role    = "production"
    owner   = var.owner_email
    Project = var.project_tag
  }
}

resource "azurerm_subnet" "production_subnet" {
  name                 = "production-subnet"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.production_vnet.name
  address_prefixes     = ["10.5.1.0/24"]
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
}

resource "azurerm_subnet_network_security_group_association" "visibility_nsg_assoc" {
  subnet_id                 = azurerm_subnet.visibility_subnet.id
  network_security_group_id = azurerm_network_security_group.nsg_visibility.id
}

# NSG for production subnet – Ubuntu VMs with UCT-V agent and VXLAN
resource "azurerm_network_security_group" "nsg_production" {
  name                = "nsg-production"
  resource_group_name = var.resource_group_name
  location            = var.location

  # SSH
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

  # UCT-V agent control/management from UCT-V Controller (TCP 9902)
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

  # VXLAN tunnel traffic to prod VMs (UDP 4789)
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

  # ICMP inbound (ping)
  security_rule {
    name                       = "Allow-ICMP-Inbound"
    priority                   = 130
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
}

resource "azurerm_subnet_network_security_group_association" "production_nsg_assoc" {
  subnet_id                 = azurerm_subnet.production_subnet.id
  network_security_group_id = azurerm_network_security_group.nsg_production.id
}

############################################################
# VNet Peering
############################################################

resource "azurerm_virtual_network_peering" "vis_to_prod" {
  name                         = "peer-visibility-to-production"
  resource_group_name          = var.resource_group_name
  virtual_network_name         = azurerm_virtual_network.visibility_vnet.name
  remote_virtual_network_id    = azurerm_virtual_network.production_vnet.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
}

resource "azurerm_virtual_network_peering" "prod_to_vis" {
  name                         = "peer-production-to-visibility"
  resource_group_name          = var.resource_group_name
  virtual_network_name         = azurerm_virtual_network.production_vnet.name
  remote_virtual_network_id    = azurerm_virtual_network.visibility_vnet.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
}
