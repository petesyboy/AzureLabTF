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

output "tool_vm_public_ip" {
  description = "Public IP address of the Tool VM (Visibility Subnet). Hosts ntopng and ends VXLAN."
  value       = module.tool_vm.public_ip
}

# UCT-V Registration Details
output "uctv_registration_info" {
  description = "UCT-V Controller registration information and configuration."
  value = {
    fm_endpoint  = "https://${module.fm.public_ip}"
    uctv_private = module.uctv.private_ip
    config_file  = "/etc/gigamon-cloud.conf"
    instructions = "UCT-V and agents automatically configured in cloud-init and via configure_lab.py."
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
      "2. Run 'python scripts/configure_lab.py' to register environment & UCT-V Controller",
      "3. Prod VMs deploy UCT-V agent and auto-register to UCT-V Controller",
      "4. SSH into prod VMs to generate traffic with iperf3",
      "5. Monitor traffic visibility through GigaVUE-FM dashboard"
    ]
  }
}

output "lab_key_pem_filename" {
  description = "The absolute path to the generated SSH private key file."
  value       = local_file.lab_key_pem.filename
}

# =============================================================================
# SSH Connection Commands
# =============================================================================
# Copy-paste ready commands to SSH into each VM

output "ssh_fm" {
  description = "SSH command for GigaVUE-FM (Fabric Manager)"
  value       = "ssh -i ${local_file.lab_key_pem.filename} ${var.admin_username}@${module.fm.public_ip}"
}

output "ssh_uctv" {
  description = "SSH command for UCT-V Controller"
  value       = "ssh -i ${local_file.lab_key_pem.filename} ${var.admin_username}@${module.uctv.public_ip}"
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
