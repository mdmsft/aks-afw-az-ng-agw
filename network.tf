resource "azurerm_virtual_network" "main" {
  name                = "vnet-${local.resource_suffix}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  address_space       = [var.address_space]
}

resource "azurerm_subnet" "cluster" {
  name                 = "snet-aks"
  virtual_network_name = azurerm_virtual_network.main.name
  resource_group_name  = azurerm_resource_group.main.name
  address_prefixes     = [cidrsubnet(var.address_space, 0, 0)]
}

resource "azurerm_network_security_group" "cluster" {
  name                = "nsg-${local.resource_suffix}-aks"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
}

resource "azurerm_subnet_network_security_group_association" "cluster" {
  network_security_group_id = azurerm_network_security_group.cluster.id
  subnet_id                 = azurerm_subnet.cluster.id
}

resource "azurerm_public_ip_prefix" "cluster" {
  name                = "ippre-${local.resource_suffix}-aks"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  prefix_length       = var.nat_gateway_public_ip_prefix_length
  sku                 = "Standard"
  zones               = ["1", "2", "3"]
}

resource "azurerm_nat_gateway" "cluster" {
  name                    = "ng-${local.resource_suffix}-aks"
  location                = azurerm_resource_group.main.location
  resource_group_name     = azurerm_resource_group.main.name
  idle_timeout_in_minutes = 4
  sku_name                = "Standard"
}

resource "azurerm_nat_gateway_public_ip_prefix_association" "cluster" {
  nat_gateway_id      = azurerm_nat_gateway.cluster.id
  public_ip_prefix_id = azurerm_public_ip_prefix.cluster.id
}

resource "azurerm_subnet_nat_gateway_association" "cluster" {
  nat_gateway_id = azurerm_nat_gateway.cluster.id
  subnet_id      = azurerm_subnet.cluster.id
}
