data "azurerm_resource_group" "existing" {
  count = var.resource_group_name != "" ? 1 : 0
  name  = var.resource_group_name
}
