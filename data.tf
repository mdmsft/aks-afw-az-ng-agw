data "azurerm_client_config" "main" {}

data "azuread_client_config" "main" {}

data "azurerm_kubernetes_service_versions" "main" {
  location        = var.location
  include_preview = false
}

data "azurerm_monitor_diagnostic_categories" "firewall" {
  count       = local.availability_zones
  resource_id = azurerm_firewall.main[count.index].id
}
