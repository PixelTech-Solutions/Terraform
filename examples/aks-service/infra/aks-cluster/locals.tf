locals {
  rg_name     = var.resource_group_name != "" ? data.azurerm_resource_group.existing[0].name : azurerm_resource_group.this[0].name
  rg_location = var.resource_group_name != "" ? data.azurerm_resource_group.existing[0].location : azurerm_resource_group.this[0].location
}
