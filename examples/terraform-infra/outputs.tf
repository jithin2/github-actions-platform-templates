output "cluster_name" {
  description = "AKS cluster name."
  value       = azurerm_kubernetes_cluster.main.name
}

output "cluster_oidc_issuer_url" {
  description = "OIDC issuer URL for Workload Identity federation."
  value       = azurerm_kubernetes_cluster.main.oidc_issuer_url
}

output "resource_group_name" {
  description = "Resource group containing all provisioned resources."
  value       = azurerm_resource_group.main.name
}
