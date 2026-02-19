# Azure Lab 6.12: Gigamon V Series Cloud Tap Deployment

This repository contains Terraform Infrastructure-as-Code (IaC) and Python automation scripts to deploy a complete Gigamon visibility fabric in Microsoft Azure. The environment demonstrates how to orchestrate third-party visibility tools (GigaVUE-FM, UCT-V, vSeries) alongside standard Azure infrastructure.

## Architecture Overview

The deployment creates a network topology designed to mirror traffic from production workloads to a dedicated tool VM for analysis.

### Infrastructure Components
1.  **GigaVUE-FM (Fabric Manager)**: The central management and orchestration plane. It communicates with the UCT-V Controller and vSeries nodes to configure traffic policies.
2.  **UCT-V Controller (Universal Cloud Tap - Virtual)**: Manages the tap points (UCT-V Agents) running on the monitored workloads.
3.  **vSeries Node**: A traffic aggregator and processor. It receives mirrored traffic from the UCT-V Agents, optimizes it, and forwards it to the tool.
4.  **Tool VM**: A Linux VM running **ntopng** for traffic visualization. It acts as the destination for the mirrored traffic, which is encapsulated in VXLAN.
5.  **Production Workloads**: Two Ubuntu VMs (`prod-ubuntu-1`, `prod-ubuntu-2`) that generate traffic. They have the **UCT-V Agent** installed to mirror their network traffic.

### Networking & Integration
-   **VNet Peering**: The `Visibility` VNet (management components) and `Production` VNet (workloads) are peered to allow seamless communication.
-   **VXLAN Tunneling**: Mirrored traffic is encapsulated in VXLAN (VNI 123) by the vSeries node and sent to the Tool VM on UDP port 4789.
-   **Automated Registration**: A Python script automates the "handshake" between the Azure infrastructure and the Gigamon management plane (see below).

## Repository Contents

*   `main.tf`: The primary Terraform configuration file defining all Azure resources (VMs, Networking, NSGs).
*   `modules/`: Reusable Terraform modules for networking and VM deployment.
*   `scripts/configure_lab.py`: Python script that serves as the "glue" code.
*   `outputs.tf`: Defines the connection details accessible after deployment.

## Automation Logic (`scripts/configure_lab.py`)

The `scripts/configure_lab.py` script is automatically triggered by Terraform after the infrastructure is provisioned. It performs the following actions to integrate the systems:

1.  **Wait for FM**: Polls the GigaVUE-FM API until the system is ready.
2.  **Authenticate**: LOGS IN to GigaVUE-FM to retrieve an API authentication token.
3.  **Configure Components**: connects via SSH to the **UCT-V Controller**, **vSeries Node**, and **Production VMs**.
4.  **Register Agents**: Updates the `/etc/gigamon-cloud.conf` file on each VM with:
    *   The FM Group and Subgroup names.
    *   The Authentication Token.
    *   The FM IP address.
5.  **Restart Services**: Restarts the `uctv-agent` service to initiate registration with the fabric.
6.  **Verify Connectivity**: Pings all nodes to ensure the management network is functional.

## Deployment Instructions

### Prerequisites
*   [Terraform](https://www.terraform.io/downloads.html) >= 1.5.0
*   [Azure CLI](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli)
*   Python 3.x (with `requests` and `paramiko` libraries)

### 1. Initialize and Deploy
Run the standard Terraform workflow:

```bash
terraform init
terraform plan -out=tfplan
terraform apply tfplan
```

### 2. Monitor Configuration
The `terraform apply` process will pause at the `null_resource.configure_lab` step while the Python script runs. This can take 5-10 minutes as it waits for the GigaVUE-FM VM to fully boot and initialize its web server.

### 3. Retrieve Connection Details
Once completed, Terraform will output the necessary IPs and credentials:

```bash
terraform output
```

Key outputs:
*   `fm_public_ip`: URL for GigaVUE-FM (https://<IP>)
*   `tool_vm_public_ip`: Access for ntopng
*   `prod1_public_ip` / `prod2_public_ip`: SSH access for traffic generation

## Usage & Verification

### 1. Connecting to the Lab
Use the SSH key generated in the project directory (`lab_key.pem`):

```bash
# Connect to Tool VM
ssh -i lab_key.pem azureuser@<tool_vm_public_ip>

# Connect to Production VM 1
ssh -i lab_key.pem azureuser@<prod1_public_ip>
```

### 2. Generating Traffic
To generate traffic that will be picked up by the visibility fabric, run `iperf3` between the production VMs.

**On Production VM 2 (Server):**
```bash
ssh -i lab_key.pem azureuser@<prod2_public_ip>
iperf3 -s
```

**On Production VM 1 (Client):**
```bash
ssh -i lab_key.pem azureuser@<prod1_public_ip>
# Replace with the PRIVATE IP of prod2 (from terraform output)
iperf3 -c 10.10.1.x -t 300
```

### 3. Verifying Visibility (ntopng)
The **Tool VM** is pre-configured with `ntopng` listening on the VXLAN interface.

1.  Open your web browser to `http://<tool_vm_public_ip>:3000`.
2.  Login with default credentials (typically `admin` / `admin`).
3.  Navigate to the **Interfaces** dropdown and select **vxlan0**.
4.  You should now see the real-time traffic flows matching your `iperf3` generation.

### 4. Viewing Raw VXLAN Traffic
If you want to see the encapsulated packets directly on the Tool VM:

```bash
# Connect to Tool VM
ssh -i lab_key.pem azureuser@<tool_vm_public_ip>

# Dump traffic on the VXLAN interface
sudo tcpdump -i vxlan0 -n
```

You should see the inner traffic (the iperf packets) being decapsulated.
