output "key_vault_name" {
  value       = azurerm_key_vault.fm_token_kv.name
  description = "The name of the Azure Key Vault."
}

output "fm_token_secret_name" {
  value       = var.fm_token_secret_name
  description = "The name of the secret for the FM API token."
}

output "fm_public_ip" {
  value       = module.fm.public_ip
  description = "The public IP address of GigaVUE-FM."
}

output "resource_group_name" {
  value       = azurerm_resource_group.rg.name
  description = "The name of the Resource Group."
}

output "location" {
  value       = azurerm_resource_group.rg.location
  description = "The Azure region."
}

output "storage_account_name" {
  value       = azurerm_storage_account.lab_sa.name
  description = "The name of the Storage Account for UCTV agents."
}

output "storage_container_name" {
  value       = azurerm_storage_container.uctv_container.name
  description = "The name of the Storage Container for UCTV agents."
}

output "ssh_fm" {
  value       = "ssh -i ./lab_key.pem ${var.admin_username}@${module.fm.public_ip}"
  description = "SSH command for GigaVUE-FM"
}

output "ssh_uctv" {
  value       = "ssh -i ./lab_key.pem ${var.admin_username}@${module.uctv_controller.public_ip}"
  description = "SSH command for UCT-V Controller"
}

output "ssh_vseries" {
  value       = "ssh -i ./lab_key.pem ${var.admin_username}@${module.vseries.public_ip}"
  description = "SSH command for vSeries Node"
}

output "ssh_tool_vm" {
  value       = "ssh -i ./lab_key.pem ${var.admin_username}@${module.tool_vm.public_ip}"
  description = "SSH command for Tool VM"
}

output "ssh_prod1" {
  value       = "ssh -i ./lab_key.pem ${var.admin_username}@${module.prod1.public_ip}"
  description = "SSH command for Production VM 1"
}

output "ssh_prod2" {
  value       = "ssh -i ./lab_key.pem ${var.admin_username}@${module.prod2.public_ip}"
  description = "SSH command for Production VM 2"
}