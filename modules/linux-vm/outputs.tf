############################################################
# Linux VM Module – Outputs
############################################################

output "public_ip" {
  description = "Public IP address of the VM."
  value       = azurerm_public_ip.pip.ip_address
}

output "vm_id" {
  description = "ID of the VM."
  value       = azurerm_linux_virtual_machine.vm.id
}
