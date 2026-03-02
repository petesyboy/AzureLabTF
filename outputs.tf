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
output "uctv_controller_public_ip" {
  description = "The public IP address of the UCT-V Controller"
  value       = module.uctv_controller.public_ip
}

output "uctv_controller_private_ip" {
  description = "The private IP address of the UCT-V Controller (Mgmt interface)"
  value       = module.uctv_controller.private_ip
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

output "tool_vm_public_ip" {
  description = "Public IP address of the Tool VM (Visibility Subnet). Hosts ntopng and ends VXLAN."
  value       = module.tool_vm.public_ip
}

# UCT-V Registration Details
output "uctv_controller_registration_info" {
  description = "Information needed to register the UCT-V Controller with FM"
  value = {
    ssh_command  = "ssh -i ${local_file.lab_key_pem.filename} ${var.admin_username}@${module.uctv_controller.public_ip}"
    uctv_private = module.uctv_controller.private_ip
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
      "2. Generate FM API token in the FM UI and upload it to Key Vault (see README)",
      "3. (Optional) Run 'python scripts/configure_lab.py' to create Monitoring Domain + Connection via FM API",
      "4. SSH into prod VMs to generate traffic with iperf3",
      "5. Monitor traffic visibility through GigaVUE-FM dashboard"
    ]
  }
}

output "lab_key_pem_filename" {
  description = "The absolute path to the generated SSH private key file."
  value       = local_file.lab_key_pem.filename
}

output "key_vault_name" {
  description = "Azure Key Vault name used to store the FM API token (JWT)."
  value       = azurerm_key_vault.fm_token_kv.name
}

output "fm_token_secret_name" {
  description = "Key Vault secret name that will contain the FM API token (JWT)."
  value       = var.fm_token_secret_name
}

# =============================================================================
# SSH Connection Commands
# =============================================================================
# Copy-paste ready commands to SSH into each VM

output "ssh_fm" {
  description = "SSH command for GigaVUE-FM (Fabric Manager)"
  value       = "ssh -i ${local_file.lab_key_pem.filename} ${var.admin_username}@${module.fm.public_ip}"
}

output "ssh_uctv_controller" {
  description = "SSH command for UCT-V Controller"
  value       = "ssh -i ${local_file.lab_key_pem.filename} ${var.admin_username}@${module.uctv_controller.public_ip}"
}

output "ssh_vseries" {
  description = "SSH command for vSeries Node"
  value       = "ssh -i ${local_file.lab_key_pem.filename} ${var.admin_username}@${module.vseries.public_ip}"
}

output "ssh_tool_vm" {
  description = "SSH command for Tool VM (ntopng / VXLAN receiver)"
  value       = "ssh -i ${local_file.lab_key_pem.filename} ${var.admin_username}@${module.tool_vm.public_ip}"
}

output "ssh_prod1" {
  description = "SSH command for Production Ubuntu VM 1"
  value       = "ssh -i ${local_file.lab_key_pem.filename} ${var.admin_username}@${module.prod1.public_ip}"
}

output "ssh_prod2" {
  description = "SSH command for Production Ubuntu VM 2"
  value       = "ssh -i ${local_file.lab_key_pem.filename} ${var.admin_username}@${module.prod2.public_ip}"
}
