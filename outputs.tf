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

output "fm_ui_url" {
  value       = "https://${module.fm.public_ip}"
  description = "Clickable URL for the GigaVUE-FM Web UI"
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

output "admin_username" {
  value       = var.admin_username
  description = "The admin username for SSH access to all VMs"
}

output "lab_key_file" {
  value       = local_file.lab_key_pem.filename
  description = "Path to the local SSH private key file"
}

output "uctv_public_ip" {
  value       = module.uctv_controller.public_ip
  description = "The public IP address of the UCT-V Controller"
}

output "vseries_public_ip" {
  value       = module.vseries.public_ip
  description = "The public IP address of the vSeries Node"
}

output "tool_vm_public_ip" {
  value       = module.tool_vm.public_ip
  description = "The public IP address of the Tool VM"
}

output "prod1_public_ip" {
  value       = module.prod1.public_ip
  description = "The public IP address of Production VM 1"
}

output "prod2_public_ip" {
  value       = module.prod2.public_ip
  description = "The public IP address of Production VM 2"
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

output "ntopng_ui_url" {
  value       = "http://${module.tool_vm.public_ip}:3000"
  description = "Clickable URL for the ntopng Web UI on the Tool VM"
}