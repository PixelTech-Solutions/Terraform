output "resource_group_name" {
  description = "Name of the resource group"
  value       = local.rg_name
}

output "cluster_name" {
  description = "Name of the AKS cluster"
  value       = module.aks.cluster_name
}

output "cluster_id" {
  description = "ID of the AKS cluster"
  value       = module.aks.cluster_id
}
