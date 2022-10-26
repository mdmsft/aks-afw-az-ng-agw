locals {
  kubernetes_cluster_orchestrator_version                    = var.kubernetes_cluster_orchestrator_version == null ? data.azurerm_kubernetes_service_versions.main.latest_version : var.kubernetes_cluster_orchestrator_version
  kubernetes_cluster_default_node_pool_orchestrator_version  = var.kubernetes_cluster_default_node_pool_orchestrator_version == null ? local.kubernetes_cluster_orchestrator_version : var.kubernetes_cluster_default_node_pool_orchestrator_version
  kubernetes_cluster_workload_node_pool_orchestrator_version = var.kubernetes_cluster_workload_node_pool_orchestrator_version == null ? local.kubernetes_cluster_orchestrator_version : var.kubernetes_cluster_workload_node_pool_orchestrator_version
}

resource "azurerm_kubernetes_cluster" "main" {
  name                              = "aks-${local.context_name}"
  location                          = azurerm_resource_group.main.location
  resource_group_name               = azurerm_resource_group.main.name
  dns_prefix                        = local.context_name
  automatic_channel_upgrade         = var.kubernetes_cluster_automatic_channel_upgrade
  role_based_access_control_enabled = true
  azure_policy_enabled              = var.kubernetes_cluster_azure_policy_enabled
  open_service_mesh_enabled         = var.kubernetes_cluster_open_service_mesh_enabled
  kubernetes_version                = local.kubernetes_cluster_orchestrator_version
  local_account_disabled            = true
  oidc_issuer_enabled               = var.kubernetes_cluster_oidc_issuer_enabled
  node_resource_group               = "rg-${local.resource_suffix}-aks"
  sku_tier                          = var.kubernetes_cluster_sku_tier
  workload_identity_enabled         = var.kubernetes_cluster_oidc_issuer_enabled && var.kubernetes_cluster_workload_identity_enabled

  azure_active_directory_role_based_access_control {
    managed            = true
    azure_rbac_enabled = true
  }

  identity {
    type = "SystemAssigned"
  }

  default_node_pool {
    name                         = "system"
    vm_size                      = var.kubernetes_cluster_default_node_pool_vm_size
    enable_auto_scaling          = true
    min_count                    = var.kubernetes_cluster_default_node_pool_min_count
    max_count                    = var.kubernetes_cluster_default_node_pool_max_count
    max_pods                     = var.kubernetes_cluster_default_node_pool_max_pods
    os_disk_size_gb              = var.kubernetes_cluster_default_node_pool_os_disk_size_gb
    os_sku                       = var.kubernetes_cluster_default_node_pool_os_sku
    orchestrator_version         = local.kubernetes_cluster_default_node_pool_orchestrator_version
    only_critical_addons_enabled = true
    vnet_subnet_id               = azurerm_subnet.cluster.id
    zones                        = var.kubernetes_cluster_default_node_pool_availability_zones

    upgrade_settings {
      max_surge = var.kubernetes_cluster_default_node_pool_max_surge
    }
  }

  oms_agent {
    log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  }

  network_profile {
    network_plugin     = var.kubernetes_cluster_network_plugin
    network_policy     = var.kubernetes_cluster_network_policy
    dns_service_ip     = cidrhost(var.kubernetes_cluster_service_cidr, 10)
    docker_bridge_cidr = var.kubernetes_cluster_docker_bridge_cidr
    service_cidr       = var.kubernetes_cluster_service_cidr
    load_balancer_sku  = "standard"
    outbound_type      = "userAssignedNATGateway"
  }

  dynamic "key_vault_secrets_provider" {
    for_each = var.kubernetes_cluster_key_vault_secrets_provider_enabled ? [{}] : []
    content {
      secret_rotation_enabled  = true
      secret_rotation_interval = "1m"
    }
  }

  dynamic "microsoft_defender" {
    for_each = var.kubernetes_cluster_microsoft_defender_enabled ? [{}] : []
    content {
      log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
    }
  }
}

resource "azurerm_kubernetes_cluster_node_pool" "main" {
  name                  = "workload"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.main.id
  vm_size               = var.kubernetes_cluster_workload_node_pool_vm_size
  enable_auto_scaling   = true
  min_count             = var.kubernetes_cluster_workload_node_pool_min_count
  max_count             = var.kubernetes_cluster_workload_node_pool_max_count
  max_pods              = var.kubernetes_cluster_workload_node_pool_max_pods
  os_disk_size_gb       = var.kubernetes_cluster_workload_node_pool_os_disk_size_gb
  os_sku                = var.kubernetes_cluster_workload_node_pool_os_sku
  orchestrator_version  = local.kubernetes_cluster_workload_node_pool_orchestrator_version
  vnet_subnet_id        = azurerm_subnet.cluster.id
  zones                 = var.kubernetes_cluster_workload_node_pool_availability_zones
  node_labels           = var.kubernetes_cluster_workload_node_pool_labels
  node_taints           = var.kubernetes_cluster_workload_node_pool_taints

  upgrade_settings {
    max_surge = var.kubernetes_cluster_workload_node_pool_max_surge
  }
}

resource "azurerm_role_assignment" "cluster_network_contributor" {
  role_definition_name = "Network Contributor"
  scope                = azurerm_subnet.cluster.id
  principal_id         = azurerm_kubernetes_cluster.main.identity.0.principal_id
}

resource "azurerm_role_assignment" "registry_pull" {
  role_definition_name = "AcrPull"
  scope                = azurerm_container_registry.main.id
  principal_id         = azurerm_kubernetes_cluster.main.kubelet_identity[0].object_id
}

resource "null_resource" "kube_config" {
  triggers = {
    cluster = azurerm_kubernetes_cluster.main.id
  }
  provisioner "local-exec" {
    command = "echo \"${azurerm_kubernetes_cluster.main.kube_config_raw}\" | tee .kubeconfig"
  }
}

resource "azurerm_role_assignment" "aks_cluster_administrator" {
  for_each             = toset(var.kubernetes_service_cluster_administrators)
  role_definition_name = "Azure Kubernetes Service Cluster Admin Role"
  principal_id         = each.value
  scope                = azurerm_kubernetes_cluster.main.id
}

resource "azurerm_role_assignment" "aks_cluster_user" {
  for_each             = toset(var.kubernetes_service_cluster_users)
  role_definition_name = "Azure Kubernetes Service Cluster User Role"
  principal_id         = each.value
  scope                = azurerm_kubernetes_cluster.main.id
}

resource "azurerm_role_assignment" "aks_rbac_administrator" {
  for_each             = toset(var.kubernetes_service_rbac_administrators)
  role_definition_name = "Azure Kubernetes Service RBAC Admin"
  principal_id         = each.value
  scope                = azurerm_kubernetes_cluster.main.id
}

resource "azurerm_role_assignment" "aks_rbac_cluster_administrator" {
  for_each             = toset(var.kubernetes_service_rbac_cluster_administrators)
  role_definition_name = "Azure Kubernetes Service RBAC Cluster Admin"
  principal_id         = each.value
  scope                = azurerm_kubernetes_cluster.main.id
}

resource "azurerm_role_assignment" "aks_rbac_reader" {
  for_each             = toset(var.kubernetes_service_rbac_readers)
  role_definition_name = "Azure Kubernetes Service RBAC Reader"
  principal_id         = each.value
  scope                = azurerm_kubernetes_cluster.main.id
}

resource "azurerm_role_assignment" "aks_rbac_writer" {
  for_each             = toset(var.kubernetes_service_rbac_writers)
  role_definition_name = "Azure Kubernetes Service RBAC Writer"
  principal_id         = each.value
  scope                = azurerm_kubernetes_cluster.main.id
}
