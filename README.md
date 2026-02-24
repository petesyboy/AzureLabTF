# Azure Lab 6.12: Gigamon V Series Cloud Tap Deployment

This repository contains Terraform Infrastructure-as-Code (IaC) and Python automation scripts to deploy a complete Gigamon V Series cloud-based traffic visibility and optimization lab environment in Microsoft Azure. The lab demonstrates third-party orchestration and management capabilities using Gigamon's GigaVUE-FM platform, rather than relying on native Azure deployment APIs. This illustrates how organizations can run independent orchestration and control planes in Azure while maintaining centralized, vendor-specific traffic management and visibility across cloud infrastructure.

## Architecture Overview

The deployment creates a complete network topology with the following design principles:

### Networking Infrastructure
- **Single Azure Virtual Network (VNet)**
  - Visibility VNet (10.0.0.0/16)
- **Two Subnets** (within the same VNet)
  - Visibility Subnet (10.0.1.0/24) - Gigamon components (FM, UCT-V, vSeries) + Tool VM
  - Production Subnet (10.0.2.0/24) - Workload VMs and traffic sources/destinations
- **Network Security Groups (NSGs)** with rules for:
  - SSH access (port 22) from admin machines
  - HTTP/HTTPS (ports 80, 443) for web interfaces
  - VXLAN traffic (UDP 4789) for overlay networking
  - Custom application ports (iperf3, ntopng, etc.)

### Gigamon Management & Control Plane (Third-Party Orchestration)

**GigaVUE-FM 6.12 (Fabric Manager)**
- Centralized third-party management and orchestration platform
- Deployed in Visibility Subnet on configurable VM size
- Accessible via HTTPS web interface on public IP
- Manages and orchestrates all UCT-V and vSeries components via Gigamon APIs
- **Note**: FM operations are INDEPENDENT of Azure Resource Management APIs
- Provides vendor-specific traffic intelligence and control outside Azure's ecosystem

**UCT-V Controller (Universal Cloud Tap - Virtual)**
- Cloud-native tap point controller managed by GigaVUE-FM
- Orchestrated through third-party Gigamon control plane (not Azure native)
- Manages packet capture and traffic mirroring independent of Azure NSGs
- Deployed in Visibility Subnet
- Communicates with FM using Gigamon proprietary protocols

**vSeries Node**
- In-line traffic processing node orchestrated by Gigamon
- Performs vendor-specific packet inspection, DPI, and optimization
- Deployed in Visibility Subnet
- Connected to both visibility and production networks for inline visibility
- Orchestration is handled by GigaVUE-FM, not Azure service fabric

### Workload & Traffic Generation

**Tool VM (tool-vm)**
- Dedicated visibility and analysis node in the Visibility Subnet
- Includes: ntopng (network traffic monitoring)
- Configured with VXLAN interface (vxlan0, VNI=123, dstport=4789) to receive mirrored traffic
- Systemd service ensures VXLAN persistence across reboots

**Production Ubuntu VM 1 (prod-ubuntu-1)**
- Complex workload with traffic analytics
- Includes: iperf3 (traffic generation)
- UCT-V Agent installed for traffic mirroring
- Can act as traffic source or destination

**Production Ubuntu VM 2 (prod-ubuntu-2)**
- Lightweight traffic generation workload
- Includes: iperf3 for benchmarking and load testing
- Used for traffic generation tests and validates vSeries processing
- Both prod VMs deployed in Production Subnet with public IPs

### Multi-Layer Orchestration Model

This lab demonstrates a **MULTI-LAYER ORCHESTRATION** approach:

**Layer 1 (Infrastructure)**: Terraform + Azure Resource Manager
- Provisions VMs, networking, storage, and IaaS resources using Azure APIs
- Provides the underlying cloud compute and network foundation

**Layer 2 (Application/Control Plane)**: GigaVUE-FM + Gigamon V Series
- Third-party orchestration platform independent of Azure Resource Manager
- Manages traffic visibility, tap points, and packet processing
- Communicates via proprietary Gigamon protocols and REST APIs
- NOT using Azure Service Fabric, Kubernetes, or ARM templates for control plane
- Illustrates how third-party platforms maintain their own orchestration layer on top of Azure infrastructure

## Technical Specifications

- **Region**: uksouth (configurable via variables)
- **Provider**: Azure Resource Manager (AzureRM) ~> 3.100
- **Terraform Version**: >= 1.5.0
- **Resource Group**: Matches the `project_name` variable (e.g., "connolly-transitory-demo-tf-3po")
- **Admin Username**: `peter` (configurable via variables, do not use 'admin' or 'root')
- **Authentication**: SSH key-based authentication for all VMs
- **Resource Tagging**: All resources tagged with project name and owner email for cost tracking

## Deployment Outputs

After successful deployment, the following outputs are available:

- `fm_public_ip` - Access the GigaVUE-FM web interface (https://<IP>)
- `uctv_public_ip` - UCT-V Controller management/troubleshooting
- `tool_vm_public_ip` - Tool VM access (SSH, ntopng UI on port 3000)
- `vseries_public_ip` - vSeries Node management/troubleshooting
- `prod1_public_ip` - Production Ubuntu VM 1 SSH access
- `prod2_public_ip` - Production Ubuntu VM 2 SSH access
- `fm_token_value` - FM authentication token (required for UCT-V/vSeries setup)

## Use Cases & Testing

This lab environment supports:

1. **Traffic Visibility Testing**: Capture and analyze traffic between prod VMs
2. **Inline Processing**: vSeries node can inspect/modify traffic in flight
3. **Network Telemetry**: ntopng on Tool VM provides real-time traffic analytics
4. **Performance Benchmarking**: iperf3 generates various load profiles
5. **VXLAN Overlay Testing**: Test encapsulated traffic over the vSeries
6. **Cloud-Native Design**: Full IaC approach with modular, reusable components

## Repository Contents

*   `variables.tf`: Input variables for the Terraform configuration (customizable settings).
*   `main.tf`: The primary Terraform configuration file defining all Azure resources (VMs, Networking, NSGs).
*   `locals.tf`: Cloud-init scripts and Ubuntu image configuration.
*   `keys.tf`: SSH key generation and management.
*   `outputs.tf`: Defines the connection details accessible after deployment.
*   `modules/`: Reusable Terraform modules for networking and VM deployment.
*   `scripts/configure_lab.py`: Python script template (generated from configure_lab.py.tftpl) that can be run manually to configure the environment.

## Automation Logic

Terraform generates a Python script (`scripts/configure_lab.py`) from the template file (`scripts/configure_lab.py.tftpl`). This script is **not automatically triggered** — you must run it manually after deployment. It performs the following actions:

1.  **Wait for FM**: Polls the GigaVUE-FM API until the system is ready.
2.  **Authenticate**: Logs into GigaVUE-FM to retrieve an API authentication token.
3.  **Configure Components**: Connects via SSH to the **UCT-V Controller**, **vSeries Node**, and **Production VMs**.
4.  **Register Agents**: Updates the `/etc/gigamon-cloud.conf` file on each VM with:
    *   The FM Group and Subgroup names.
    *   The Authentication Token.
    *   The FM IP address.
5.  **Install UCT-V Agent**: The agent is automatically downloaded from a public Azure Blob Storage URL (`https://connollystorageaccount.blob.core.windows.net/uctv-agents/...`) and installed via cloud-init.
6.  **Restart Services**: Restarts the `uctv-agent` service to initiate registration with the fabric.
7.  **Verify Connectivity**: Pings all nodes to ensure the management network is functional.

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

### 2. Post-Deployment Configuration (CRITICAL)

The deployment creates the infrastructure, but GigaVUE-FM requires manual initialization and token generation.

1.  **Access GigaVUE-FM**:
    *   Once `terraform apply` finishes, get the FM IP: `terraform output fm_public_ip`
    *   Open `https://<fm_public_ip>` in your browser.
    *   Login with default credentials: `admin` / `admin123A!!`
    *   **Uncheck** "SSH Key-Based Authentication" if prompted.
    *   **Change the Password** when prompted.

2.  **Generate API Token**:
    *   In FM, go to **User Profile** (top right icon) > **API Token**.
    *   Click **Generate**.
    *   **Copy** the token to your clipboard.

3.  **Run Automation Script**:
    From your terminal in the project root:
    ```bash
    # On macOS/Linux:
    python3 scripts/configure_lab.py
    
    # On Windows:
    python scripts/configure_lab.py
    ```
    *   **Paste** the API token when prompted.
    *   The script will configure all agents and create the Monitoring Domain/Session automatically.

### 3. Retrieve Connection Details
Once configured, you can access the environment using the generated key `lab_key.pem`:

```bash
terraform output
```

Key outputs:
*   `fm_public_ip`: URL for GigaVUE-FM
*   `tool_vm_public_ip`: Access for ntopng
*   `prod1_public_ip` / `prod2_public_ip`: SSH access for traffic generation

## Usage & Verification

### 1. Connecting to the Lab
Use the SSH key generated in the project directory (`lab_key.pem`). The default admin username is `peter`:

```bash
# Connect to Tool VM
ssh -i lab_key.pem peter@<tool_vm_public_ip>

# Connect to Production VM 1
ssh -i lab_key.pem peter@<prod1_public_ip>
```

### 2. Generating Traffic
To generate traffic that will be picked up by the visibility fabric, run `iperf3` between the production VMs.

**On Production VM 2 (Server):**
```bash
ssh -i lab_key.pem peter@<prod2_public_ip>
iperf3 -s
```

**On Production VM 1 (Client):**
```bash
ssh -i lab_key.pem peter@<prod1_public_ip>
# Replace with the PRIVATE IP of prod2 (from terraform output)
iperf3 -c 10.0.2.x -t 300
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
ssh -i lab_key.pem peter@<tool_vm_public_ip>

# Dump traffic on the VXLAN interface
sudo tcpdump -i vxlan0 -n
```

You should see the inner traffic (the iperf packets) being decapsulated.
