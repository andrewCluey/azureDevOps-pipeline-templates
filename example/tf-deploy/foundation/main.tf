resource "azurerm_resource_group" "pipeline_demo" {
  name     = var.rg_name
  location = "uksouth"
}

variable "rg_name" {
}