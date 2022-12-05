resource "azurerm_virtual_network" "cluster" {
  name                = "vnet-${local.resource_suffix}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  address_space       = [var.address_space]
}

resource "azurerm_subnet" "application_gateway" {
  name                 = "snet-agw"
  virtual_network_name = azurerm_virtual_network.cluster.name
  resource_group_name  = azurerm_resource_group.main.name
  address_prefixes     = [cidrsubnet(var.address_space, 3, 0)]
}

resource "azurerm_subnet" "cluster" {
  name                 = "snet-aks"
  virtual_network_name = azurerm_virtual_network.cluster.name
  resource_group_name  = azurerm_resource_group.main.name
  address_prefixes     = [cidrsubnet(var.address_space, 3, 1)]
}

resource "azurerm_subnet" "node_pool" {
  count                = local.availability_zones
  name                 = "snet-aks-${count.index + 1}"
  virtual_network_name = azurerm_virtual_network.cluster.name
  resource_group_name  = azurerm_resource_group.main.name
  address_prefixes     = [cidrsubnet(var.address_space, 2, count.index + 1)]
}

resource "azurerm_network_security_group" "cluster" {
  name                = "nsg-${local.resource_suffix}-aks"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
}

resource "azurerm_network_security_group" "node_pool" {
  count               = local.availability_zones
  name                = "nsg-${local.resource_suffix}-aks-${count.index + 1}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
}

resource "azurerm_subnet_network_security_group_association" "cluster" {
  network_security_group_id = azurerm_network_security_group.cluster.id
  subnet_id                 = azurerm_subnet.cluster.id
}

resource "azurerm_subnet_network_security_group_association" "node_pool" {
  count                     = local.availability_zones
  network_security_group_id = azurerm_network_security_group.node_pool[count.index].id
  subnet_id                 = azurerm_subnet.node_pool[count.index].id
}

resource "azurerm_route_table" "node_pool" {
  count               = local.availability_zones
  name                = "rt-${local.resource_suffix}-${count.index}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  route {
    name                   = "net-to-afw"
    address_prefix         = "0.0.0.0/0"
    next_hop_in_ip_address = azurerm_firewall.main[count.index].ip_configuration.0.private_ip_address
    next_hop_type          = "VirtualAppliance"
  }

  route {
    name           = "afw-to-www"
    address_prefix = "${azurerm_public_ip.firewall[count.index].ip_address}/32"
    next_hop_type  = "Internet"
  }
}

resource "azurerm_subnet_route_table_association" "node_pool" {
  count          = local.availability_zones
  subnet_id      = azurerm_subnet.node_pool[count.index].id
  route_table_id = azurerm_route_table.node_pool[count.index].id
}

resource "azurerm_virtual_network" "firewall" {
  count               = local.availability_zones
  name                = "vnet-${local.resource_suffix}-afw-${count.index + 1}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  address_space       = [cidrsubnet(var.firewall_address_space, 2, count.index)]
}

resource "azurerm_subnet" "firewall" {
  count                = local.availability_zones
  name                 = "AzureFirewallSubnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.firewall[count.index].name
  address_prefixes     = azurerm_virtual_network.firewall[count.index].address_space
}

resource "azurerm_public_ip_prefix" "firewall" {
  count               = local.availability_zones
  name                = "ippre-${local.resource_suffix}-ng-${count.index + 1}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  prefix_length       = var.nat_gateway_public_ip_prefix_length
  sku                 = "Standard"
  zones               = [tostring(count.index + 1)]
}

resource "azurerm_nat_gateway" "firewall" {
  count                   = local.availability_zones
  name                    = "ng-${local.resource_suffix}-afw-${count.index + 1}"
  location                = azurerm_resource_group.main.location
  resource_group_name     = azurerm_resource_group.main.name
  idle_timeout_in_minutes = 4
  sku_name                = "Standard"
  zones                   = [tostring(count.index + 1)]
}

resource "azurerm_nat_gateway_public_ip_prefix_association" "firewall" {
  count               = local.availability_zones
  nat_gateway_id      = azurerm_nat_gateway.firewall[count.index].id
  public_ip_prefix_id = azurerm_public_ip_prefix.firewall[count.index].id
}

resource "azurerm_subnet_nat_gateway_association" "firewall" {
  count          = local.availability_zones
  nat_gateway_id = azurerm_nat_gateway.firewall[count.index].id
  subnet_id      = azurerm_subnet.firewall[count.index].id
}

resource "azurerm_virtual_network_peering" "cluster_firewall" {
  count                        = local.availability_zones
  name                         = azurerm_virtual_network.firewall[count.index].name
  resource_group_name          = azurerm_resource_group.main.name
  virtual_network_name         = azurerm_virtual_network.cluster.name
  remote_virtual_network_id    = azurerm_virtual_network.firewall[count.index].id
  allow_forwarded_traffic      = true
  allow_virtual_network_access = true
}

resource "azurerm_virtual_network_peering" "firewall_cluster" {
  count                        = local.availability_zones
  name                         = azurerm_virtual_network.cluster.name
  resource_group_name          = azurerm_resource_group.main.name
  virtual_network_name         = azurerm_virtual_network.firewall[count.index].name
  remote_virtual_network_id    = azurerm_virtual_network.cluster.id
  allow_forwarded_traffic      = true
  allow_virtual_network_access = true
}
