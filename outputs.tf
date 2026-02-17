############################################################
# Outputs
############################################################

output "fm_public_ip" {
  description = "Public IP address of GigaVUE-FM."
  value       = module.fm.public_ip
}

output "uctv_public_ip" {
  description = "Public IP address of UCT-V Controller."
  value       = module.uctv.public_ip
}

output "vseries_public_ip" {
  description = "Public IP address of vSeries node."
  value       = module.vseries.public_ip
}

output "prod1_public_ip" {
  description = "Public IP address of production Ubuntu VM 1."
  value       = module.prod1.public_ip
}

output "prod2_public_ip" {
  description = "Public IP address of production Ubuntu VM 2."
  value       = module.prod2.public_ip
}

output "fm_token_value" {
  description = "FM token string to copy into /etc/gigamon-cloud.conf on UCT-V and vSeries."
  value       = random_string.fm_token.result
  sensitive   = true
}
