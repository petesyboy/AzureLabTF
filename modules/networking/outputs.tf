############################################################
# Networking Module – Outputs
############################################################

output "visibility_subnet_id" {
  description = "ID of the visibility subnet."
  value       = azurerm_subnet.visibility_subnet.id
}

output "production_subnet_id" {
  description = "ID of the production subnet."
  value       = azurerm_subnet.production_subnet.id
}
