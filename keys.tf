# SSH Key Management
# Generates a new SSH key pair for this deployment to ensure secure access.
# The private key is saved locally to allow configuration scripts to SSH into VMs.

resource "tls_private_key" "lab_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "local_file" "lab_key_pem" {
  content         = tls_private_key.lab_key.private_key_pem
  filename        = "${path.module}/lab_key.pem"
  file_permission = "0600"
}
