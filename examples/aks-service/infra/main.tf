variable "environment" {
  type    = string
  default = "dev"
}

variable "location" {
  type    = string
  default = "eastus"
}

variable "resource_group_name" {
  type    = string
  default = "rg-aks-example"
}

resource "azurerm_resource_group" "this" {
  name     = "${var.resource_group_name}-${var.environment}"
  location = var.location

  tags = {
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# Example: teams just add their Azure resources here
# The pipeline handles everything else
output "resource_group_id" {
  value = azurerm_resource_group.this.id
}
