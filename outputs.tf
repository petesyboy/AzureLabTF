# =============================================================================
# Outputs
# =============================================================================
# These values are returned after `terraform apply` completes.
# They provide connection details for the deployed resources.
# Usage: terraform output <output_name>

output "fm_public_ip" {
  description = "Public IP address of GigaVUE-FM. Use this to access the FM web interface (https://<IP>)."
  value       = module.fm.public_ip
}

output "uctv_public_ip" {
  description = "Public IP address of UCT-V Controller. Used for troubleshooting/maintenance."
  value       = module.uctv.public_ip
}

output "vseries_public_ip" {
  description = "Public IP address of vSeries node. Used for troubleshooting/maintenance."
  value       = module.vseries.public_ip
}

output "prod1_public_ip" {
  description = "Public IP address of production Ubuntu VM 1 (Traffic Source/Destination)."
  value       = module.prod1.public_ip
}

output "prod2_public_ip" {
  description = "Public IP address of production Ubuntu VM 2 (Traffic Source/Destination)."
  value       = module.prod2.public_ip
}

output "fm_token_value" {
  description = "FM token string to copy into /etc/gigamon-cloud.conf on UCT-V and vSeries."
  value       = random_string.fm_token.result
  sensitive   = true # This prevents the value from being shown in cleartext in CLI output
}
