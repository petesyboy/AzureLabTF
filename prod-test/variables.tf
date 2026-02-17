variable "location" {
  type        = string
  default     = "uksouth"
  description = "Azure region to deploy resources in."
}

variable "admin_username" {
  type        = string
  default     = "peter"
  description = "Admin username for SSH access to VMs."
}

variable "admin_ssh_public_key" {
  type        = string
  description = "SSH public key used for admin access to VMs."
  default     = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQC3ox6dPw15tN4XqpgyA7iji2o4VcDFM8tj3gZsTu+d7z8gTGPsYyJ8NmppHDsm6lnUSgdVxCZTzCAXZ2AGNiUTyYMvL6afYLEN0Gb2a1bSpES7nRZZp+aS8dBITNRMqW05AL8NaVoDEKAiU5YNohbHMxwJ4uNKl/P77On1R2W53h1IwjCCSr2YMR4g9CEy7Nkxt9fO+1xPORn0ComEyk6zxrnLN4vaOIaP1B3n0qbDu/6dEzQZ4a1sCkCJsyBKuJ5UZSwVCJEGxi1vmRj+BpInM/ktC91WpLuuDi9dGuGTlX6BFn73bbQTyYfdnPl86AuEHmak7m80N+G45ts/hcs9eEVWRDhdQxF9FjepC4ZG6TWR4YOay10Cn0MM4BCHe/NmePLhsoXKrBplgVwxiutL9DqwzFND4FpJAzIQ9lIzQdhmx47lP24FGuUN7JXl7RBW/RE0YC6rNXkbQqWmchohfgrieVXxhYsZTITfz7eBD/e5qouPo35iksvoSRr/RO0= generated-by-azure"
}

variable "gigamon_email" {
  type        = string
  description = "Email address used as the owner tag on resources."
  default     = "pete.connolly@gigamon.com"
}

variable "ubuntu_vm_size" {
  type    = string
  default = "Standard_B2s"
}

variable "ubuntu_version" {
  type        = string
  description = "Ubuntu release to use for VM images. Allowed: \"22.04\" or \"24.04\"."
  default     = "24.04"
}
