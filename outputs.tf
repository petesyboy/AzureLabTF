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