# =============================================================================
# Outputs
# =============================================================================
# These values are returned after `terraform apply` completes.
# They provide connection details for the deployed resources.
# Usage: terraform output <output_name>

# =============================================================================
# VM Names
# =============================================================================

output "vm_names" {
  description = "The names of the VMs created in this resource group, prefixed with 'connolly'."
  value = {
    fm              = "connolly-fm-${replace(var.gigamon_version, ".", "")}"
    uctv_controller = "connolly-uctv-controller"
    vseries         = "connolly-vseries-node"
    tool_vm         = "connolly-tool-vm"
    prod1           = "connolly-prod-ubuntu-1"
    prod2           = "connolly-prod-ubuntu-2"
  }
}

output "internal_fqdns" {
  description = "Internal Fully Qualified Domain Names for the VMs (accessible within the VNet)."
  value = {
    fm              = "fm.connolly.lab"
    uctv_controller = "uctv.connolly.lab"
    vseries         = "vseries.connolly.lab"
    tool_vm         = "tool.connolly.lab"
    prod1           = "prod1.connolly.lab"
    prod2           = "prod2.connolly.lab"
  }
}

output "public_fqdns" {
  description = "Public Fully Qualified Domain Names for the VMs."
  value = {
    fm              = "connolly-fm-${replace(var.gigamon_version, ".", "")}-${random_string.kv_suffix.result}.${var.location}.cloudapp.azure.com"
    uctv_controller = "connolly-uctv-${random_string.kv_suffix.result}.${var.location}.cloudapp.azure.com"
    vseries         = "connolly-vseries-${random_string.kv_suffix.result}.${var.location}.cloudapp.azure.com"
    tool_vm         = "connolly-tool-${random_string.kv_suffix.result}.${var.location}.cloudapp.azure.com"
    prod1           = "connolly-prod1-${random_string.kv_suffix.result}.${var.location}.cloudapp.azure.com"
    prod2           = "connolly-prod2-${random_string.kv_suffix.result}.${var.location}.cloudapp.azure.com"
  }
}

# GigaVUE-FM Outputs
output "fm_public_ip" {
  description = "Public IP address of GigaVUE-FM (connolly-fm-...). Use this to access the FM web interface (https://<IP>)."
  value       = module.fm.public_ip
}

output "fm_private_ip" {
  description = "Private IP address of GigaVUE-FM (internal visibility subnet)."
  value       = module.fm.private_ip
}

output "fm_url" {
  description = "HTTPS URL for GigaVUE-FM management interface."
  value       = "https://connolly-fm-${replace(var.gigamon_version, ".", "")}-${random_string.kv_suffix.result}.${var.location}.cloudapp.azure.com"
}

# UCT-V Controller Outputs
output "uctv_controller_public_ip" {
  description = "The public IP address of the UCT-V Controller (connolly-uctv-controller)"
  value       = module.uctv_controller.public_ip
}

output "uctv_controller_private_ip" {
  description = "The private IP address of the UCT-V Controller (Mgmt interface)"
  value       = module.uctv_controller.private_ip
}

# vSeries Node Outputs
output "vseries_public_ip" {
  description = "Public IP address of vSeries node (connolly-vseries-node). Used for troubleshooting/maintenance."
  value       = module.vseries.public_ip
}

output "vseries_private_ip" {
  description = "Private IP address of vSeries node (internal visibility subnet)."
  value       = module.vseries.private_ip
}

# Production VMs Outputs
output "prod1_public_ip" {
  description = "Public IP address of production Ubuntu VM 1 (connolly-prod-ubuntu-1). SSH: ssh -i key.pem peter@<IP>"
  value       = module.prod1.public_ip
}

output "prod1_private_ip" {
  description = "Private IP address of prod1 (internal production subnet). Used for traffic generation."
  value       = module.prod1.private_ip
}

output "prod2_public_ip" {
  description = "Public IP address of production Ubuntu VM 2 (connolly-prod-ubuntu-2). SSH: ssh -i key.pem peter@<IP>"
  value       = module.prod2.public_ip
}

output "prod2_private_ip" {
  description = "Private IP address of prod2 (internal production subnet). Used for traffic generation."
  value       = module.prod2.private_ip
}

output "tool_vm_public_ip" {
  description = "Public IP address of the Tool VM (connolly-tool-vm). Hosts ntopng and ends VXLAN."
  value       = module.tool_vm.public_ip
}

output "tool_vm_ntopng_url" {
  description = "URL to access ntopng on the Tool VM."
  value       = "http://connolly-tool-${random_string.kv_suffix.result}.${var.location}.cloudapp.azure.com:3000"
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
  description = "SSH command for GigaVUE-FM (connolly-fm-...)"
  value       = "ssh -i ${local_file.lab_key_pem.filename} ${var.admin_username}@connolly-fm-${replace(var.gigamon_version, ".", "")}-${random_string.kv_suffix.result}.${var.location}.cloudapp.azure.com"
}

output "ssh_uctv_controller" {
  description = "SSH command for UCT-V Controller (connolly-uctv-controller)"
  value       = "ssh -i ${local_file.lab_key_pem.filename} ${var.admin_username}@connolly-uctv-${random_string.kv_suffix.result}.${var.location}.cloudapp.azure.com"
}

output "ssh_vseries" {
  description = "SSH command for vSeries Node (connolly-vseries-node)"
  value       = "ssh -i ${local_file.lab_key_pem.filename} ${var.admin_username}@connolly-vseries-${random_string.kv_suffix.result}.${var.location}.cloudapp.azure.com"
}

output "ssh_tool_vm" {
  description = "SSH command for Tool VM (connolly-tool-vm)"
  value       = "ssh -i ${local_file.lab_key_pem.filename} ${var.admin_username}@connolly-tool-${random_string.kv_suffix.result}.${var.location}.cloudapp.azure.com"
}

output "ssh_prod1" {
  description = "SSH command for Production Ubuntu VM 1 (connolly-prod-ubuntu-1)"
  value       = "ssh -i ${local_file.lab_key_pem.filename} ${var.admin_username}@connolly-prod1-${random_string.kv_suffix.result}.${var.location}.cloudapp.azure.com"
}

output "ssh_prod2" {
  description = "SSH command for Production Ubuntu VM 2 (connolly-prod-ubuntu-2)"
  value       = "ssh -i ${local_file.lab_key_pem.filename} ${var.admin_username}@connolly-prod2-${random_string.kv_suffix.result}.${var.location}.cloudapp.azure.com"
}
