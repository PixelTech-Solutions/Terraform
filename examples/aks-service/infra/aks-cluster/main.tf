resource "azurerm_resource_group" "this" {
  count    = var.resource_group_name == "" ? 1 : 0
  name     = "rg-${var.project_name}-${var.environment}"
  location = var.location

  tags = {
    Environment = var.environment
    Project     = var.project_name
    ManagedBy   = "Terraform"
  }
}

module "aks" {
  source = "../modules/aks"

  project_name        = var.project_name
  environment         = var.environment
  location            = local.rg_location
  resource_group_name = local.rg_name
  node_count          = var.node_count
  vm_size             = var.vm_size
}
