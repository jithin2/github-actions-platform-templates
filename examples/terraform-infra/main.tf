# Example infrastructure root module.
# Provisions an AKS cluster with supporting networking using the same
# patterns as the terraform-portfolio reusable modules.
#
# In a real team repo this file is the entry point for the team's infra.
# The platform team owns the pipeline (infra.yml); the product team owns
# what gets provisioned here.

locals {
  common_tags = {
    environment = var.environment
    application = var.application
    managed_by  = "terraform"
  }
  name_prefix = "${var.environment}-${var.application}"
}

resource "azurerm_resource_group" "main" {
  name     = "rg-${local.name_prefix}"
  location = var.location
  tags     = local.common_tags
}

# ── Networking ────────────────────────────────────────────────────────────────
resource "azurerm_virtual_network" "main" {
  name                = "vnet-${local.name_prefix}"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.common_tags
}

resource "azurerm_subnet" "aks_system" {
  name                 = "snet-aks-system"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.0.0.0/22"]
}

resource "azurerm_subnet" "aks_user" {
  name                 = "snet-aks-user"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.0.4.0/22"]
}

# ── AKS cluster ───────────────────────────────────────────────────────────────
resource "azurerm_kubernetes_cluster" "main" {
  name                = "aks-${local.name_prefix}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  dns_prefix          = local.name_prefix
  tags                = local.common_tags

  default_node_pool {
    name                 = "system"
    vm_size              = "Standard_D4ds_v5"
    min_count            = 1
    max_count            = 3
    vnet_subnet_id       = azurerm_subnet.aks_system.id
    auto_scaling_enabled = true
  }

  identity {
    type = "SystemAssigned"
  }

  oidc_issuer_enabled       = true
  workload_identity_enabled = true

  network_profile {
    network_plugin = "azure"
    outbound_type  = "loadBalancer"
  }

  lifecycle {
    # Prevent plan drift from AKS auto-upgrade — same pattern as terraform-portfolio.
    ignore_changes = [kubernetes_version, default_node_pool[0].orchestrator_version]
  }
}
