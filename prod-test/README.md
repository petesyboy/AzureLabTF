Created a minimal Terraform test workspace that only deploys the two production Ubuntu VMs.

Quick start:

1. Change into the test folder:

```bash
cd prod-test
```

2. (Optional) Override the `admin_ssh_public_key` variable with your own key:

```bash
terraform init
terraform apply -var 'admin_ssh_public_key="ssh-rsa AAAA... your key ..."'
```

3. To use defaults (sample key provided) run:

```bash
terraform init
terraform apply
```

Notes:
- This workspace is independent from the root Terraform files and state.
- It creates a resource group, VNet/subnet, NSG, two public IPs, NICs, and the two Ubuntu VMs.
