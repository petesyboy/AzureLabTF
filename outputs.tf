# =============================================================================
# Outputs
# =============================================================================
# These values are returned after `terraform apply` completes.
# They provide connection details for the deployed resources.
# Usage: terraform output <output_name>

# GigaVUE-FM Outputs
output "fm_public_ip" {
  description = "Public IP address of GigaVUE-FM. Use this to access the FM web interface (https://<IP>)."
  value       = module.fm.public_ip
}

output "fm_private_ip" {
  description = "Private IP address of GigaVUE-FM (internal visibility subnet)."
  value       = module.fm.private_ip
}

# UCT-V Controller Outputs
output "uctv_public_ip" {
  description = "Public IP address of UCT-V Controller. Used for troubleshooting/maintenance."
  value       = module.uctv.public_ip
}

output "uctv_private_ip" {
  description = "Private IP address of UCT-V Controller (internal visibility subnet). Agents register to this address."
  value       = module.uctv.private_ip
}

# vSeries Node Outputs
output "vseries_public_ip" {
  description = "Public IP address of vSeries node. Used for troubleshooting/maintenance."
  value       = module.vseries.public_ip
}

output "vseries_private_ip" {
  description = "Private IP address of vSeries node (internal visibility subnet)."
  value       = module.vseries.private_ip
}

# Production VMs Outputs
output "prod1_public_ip" {
  description = "Public IP address of production Ubuntu VM 1 (Traffic Source/Destination). SSH: ssh -i key.pem peter@<IP>"
  value       = module.prod1.public_ip
}

output "prod1_private_ip" {
  description = "Private IP address of prod1 (internal production subnet). Used for traffic generation."
  value       = module.prod1.private_ip
}

output "prod2_public_ip" {
  description = "Public IP address of production Ubuntu VM 2 (Traffic Source/Destination). SSH: ssh -i key.pem peter@<IP>"
  value       = module.prod2.public_ip
}

output "prod2_private_ip" {
  description = "Private IP address of prod2 (internal production subnet). Used for traffic generation."
  value       = module.prod2.private_ip
}

# FM Token Output
output "fm_token_value" {
  description = "FM token string. Copy to /etc/gigamon-cloud.conf on UCT-V and UCT-V agents for authentication."
  value       = random_string.fm_token.result
  sensitive   = true # This prevents the value from being shown in cleartext in CLI output
}

# UCT-V Registration Details
output "uctv_registration_info" {
  description = "UCT-V Controller registration information and configuration."
  value = {
    fm_endpoint  = "https://${module.fm.public_ip}"
    fm_token     = "Use 'terraform output fm_token_value' to retrieve"
    uctv_private = module.uctv.private_ip
    config_file  = "/etc/gigamon-cloud.conf"
    instructions = "UCT-V and agents automatically configured in cloud-init. Copy FM token if manual setup needed."
  }
}

# Deployment Summary
output "deployment_summary" {
  description = "Summary of the third-party orchestration environment and next steps."
  value = {
    architecture = "Third-party orchestration: GigaVUE-FM coordinates UCT-V and vSeries (not Azure service fabric)"
    fm_url       = "https://${module.fm.public_ip}"
    ssh_user     = var.admin_username
    ssh_key      = "Provide your SSH key for authentication"
    next_steps = [
      "1. Access FM web interface using fm_public_ip",
      "2. UCT-V Controller auto-registers to FM using FM token",
      "3. Prod VMs deploy UCT-V agent and auto-register to UCT-V Controller",
      "4. SSH into prod VMs to generate traffic with iperf3",
      "5. Monitor traffic visibility through GigaVUE-FM dashboard"
    ]
  }
}
