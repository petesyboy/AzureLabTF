import requests
import time
import json
import sys
import urllib3
import os
import subprocess
import shutil

# Suppress insecure request warnings
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

# ==============================================================================
# CONFIGURATION (Populated by Terraform)
# ==============================================================================
FM_IP = "51.11.156.226"
FM_URL = f"https://{FM_IP}"

# FM Configuration Defaults
FM_GROUP = "Azure-3PO-MD"
FM_SUBGROUP = "Azure-3PO-Connection"
VSERIES_IP = "20.50.122.250"
UCTV_CONTROLLER_IP = "40.120.39.222"
PROD1_IP = "51.11.33.147"
PROD2_IP = "20.90.108.83"

# Azure Key Vault (optional convenience for local script)
# If you uploaded the FM token to Key Vault, this script can read it using Azure CLI.
KEY_VAULT_NAME = "kv1wqrypwi"
FM_TOKEN_SECRET_NAME = "gigamon-fm-token"

# FM API Token — leave empty to be prompted at runtime.
# Generate from FM UI: Administration > User Management > Tokens > Current User Tokens
# Token is used for both FM REST API calls and agent registration in gigamon-cloud.conf
FM_TOKEN = ""

# Built at runtime after token is obtained
AUTH_HEADERS = {}

def check_fm_accessible():
    """Checks if FM API is reachable and ready."""
    url = f"{FM_URL}/api/v1.3/user" 
    print(f"Waiting for FM API to become ready (this can take 5-10 minutes after boot)...")
    print(f"Checking URL: {url} for a valid JSON API response")
    
    max_retries = 60
    for i in range(max_retries):
        try:
            # Send a request with dummy auth. If the API is up, it will return a 401/403 with JSON.
            # If the web server is up but API isn't, it often returns 502, 503, or an HTML redirect.
            resp = requests.get(url, verify=False, timeout=5, auth=("dummy", "dummy"))
            
            # If the response contains JSON, it means the backend API has initialized
            if "application/json" in resp.headers.get("Content-Type", ""):
                print("\nFM API is ready!")
                return True
            else:
                sys.stdout.write(".")
                sys.stdout.flush()
        except requests.exceptions.RequestException:
            sys.stdout.write("_")
            sys.stdout.flush()
        
        time.sleep(10)
        
    print("\nTimeout waiting for FM API. Please check the VM status.")
    return False

def get_auth_token():
    """
    Retrieves the FM API token directly from Azure Key Vault using the Azure CLI.
    This avoids attempting to login to FM programmatically.
    """
    print(f"Retrieving FM API Token from Azure Key Vault '{KEY_VAULT_NAME}' (Secret: '{FM_TOKEN_SECRET_NAME}')...")

    try:
        # Construct the Azure CLI command to get the secret
        cmd = [
            "az", "keyvault", "secret", "show",
            "--vault-name", KEY_VAULT_NAME,
            "--name", FM_TOKEN_SECRET_NAME,
            "--query", "value",
            "-o", "tsv"
        ]

        # Execute the command
        result = subprocess.run(cmd, capture_output=True, text=True, check=True)
        token = result.stdout.strip()

        if not token:
            print("Error: Retrieved token is empty.")
            sys.exit(1)

        print("Successfully retrieved token from Key Vault.")
        return token

    except subprocess.CalledProcessError as e:
        print(f"Error calling Azure CLI: {e}")
        print(f"Error Output: {e.stderr}")
        print("Ensure you are logged in with 'az login' and have access to the Key Vault.")
        sys.exit(1)
    except Exception as e:
        print(f"An unexpected error occurred while retrieving the token: {e}")
        sys.exit(1)

def create_monitoring_domain(domain_alias):
    """Creates the Monitoring Domain via FM API using 'anyCloud' platform."""
    url = f"{FM_URL}/api/v1.3/cloud/monitoringDomains"

    # 1. Check existence
    print(f"Checking for existing domain at: {url}")
    try:
        resp = requests.get(url, headers=AUTH_HEADERS, verify=False)
        print(f"GET Response Code: {resp.status_code}")
        
        if resp.status_code == 200:
            try:
                data = resp.json()
                print(f"DEBUG: Domains Raw Response: {json.dumps(data, indent=2)}")
                
                # Handle wrapped response (common in Gigamon APIs)
                if isinstance(data, dict) and 'monitoringDomains' in data:
                    domains = data['monitoringDomains']
                elif isinstance(data, list):
                    domains = data
                else:
                    domains = [data] if isinstance(data, dict) else []

                for d in domains:
                    # Handle if d is a dict (expected)
                    if isinstance(d, dict) and d.get('alias') == domain_alias:
                        print(f"Monitoring Domain '{domain_alias}' already exists (ID: {d.get('id')}).")
                        return d.get('id')
                        
            except ValueError:
                print(f"GET Response was not JSON: {resp.text}")
                
        else:
            print(f"Failed to list domains. Status: {resp.status_code}")
            print(f"Response: {resp.text}")
    except Exception as e:
        print(f"Warning: Could not list cloud domains: {e}")

    # 2. Create
    print(f"\nCreating Monitoring Domain '{domain_alias}'...")
    
    # User provided payload
    payload = {
        "alias": domain_alias,
        "platform": "anyCloud",
        "userLaunched": True,
        "dualStackPreferIPv6": False,
        "mtu": 1450
    }

    try:
        response = requests.post(url, json=payload, headers=AUTH_HEADERS, verify=False)
        
        # Debugging POST response
        print(f"POST Response Code: {response.status_code}")
        
        if response.status_code in [200, 201]:
            # Try to get ID from response first
            try:
                data = response.json()
                if data and 'id' in data:
                    domain_id = data.get('id')
                    print(f"Successfully created Monitoring Domain (ID: {domain_id}).")
                    return domain_id
            except:
                pass
            
            print(f"POST succeeded ({response.status_code}). Retrieving ID via GET...")
            
            # Attempt to retrieve ID via GET since creation succeeded
            # Wait a moment for consistency?
            time.sleep(2) 
            try:
                resp = requests.get(url, headers=AUTH_HEADERS, verify=False)
                if resp.status_code == 200:
                    data = resp.json()
                    if isinstance(data, dict) and 'monitoringDomains' in data:
                        domains = data['monitoringDomains']
                    elif isinstance(data, list):
                        domains = data
                    else:
                        domains = []

                    for d in domains:
                        if isinstance(d, dict) and d.get('alias') == domain_alias:
                            print(f"Retrieved ID for newly created Domain: {d.get('id')}")
                            return d.get('id')
            except Exception as e:
                print(f"Error retrieving ID after creation: {e}")
                
            print("[!] Created Domain but could not retrieve ID automatically.")
            return None
                
        elif response.status_code == 409:
            # Non-interactive: domain exists; retrieve ID and continue.
            print(f"Monitoring Domain '{domain_alias}' already exists (409 Conflict). Retrieving its ID...")
            try:
                resp = requests.get(url, headers=AUTH_HEADERS, verify=False)
                if resp.status_code == 200:
                    data = resp.json()
                    if isinstance(data, dict) and 'monitoringDomains' in data:
                        domains = data['monitoringDomains']
                    elif isinstance(data, list):
                        domains = data
                    else:
                        domains = []

                    for d in domains:
                        if isinstance(d, dict) and d.get('alias') == domain_alias:
                            print(f"Found existing Domain ID: {d.get('id')}")
                            return d.get('id')
                print("[!] Domain exists but could not retrieve ID from API listing.")
                return None
            except Exception as e:
                print(f"[!] Domain exists but GET retry failed: {e}")
                return None
        else:
            print(f"Failed to create Monitoring Domain. API returned {response.status_code}")
            print(f"Response: {response.text}")
            return None
    except Exception as e:
        print(f"Error creating domain: {e}")
        return None

def create_anycloud_connection(domain_id, connection_alias):
    """Creates the AnyCloud Connection (Session) via FM API."""
    if not domain_id:
        print("Skipping Connection/Session creation (No Domain ID).")
        return

    url = f"{FM_URL}/api/v1.3/cloud/anyCloud/connections"

    print(f"\nCreating AnyCloud Connection '{connection_alias}'...")

    payload = {
        "alias": connection_alias,
        "monitoringDomainId": domain_id,
        "secureMirrorTraffic": False
    }

    try:
        response = requests.post(url, json=payload, headers=AUTH_HEADERS, verify=False)
        print(f"POST Response Code: {response.status_code}")
        
        if response.status_code in [200, 201]:
            print(f"Successfully created AnyCloud Connection '{connection_alias}'.")
        elif response.status_code == 409:
            print(f"AnyCloud Connection '{connection_alias}' already exists.")
        else:
            print(f"Failed to create Connection. API returned {response.status_code}")
            print(f"Response: {response.text}")
            
    except Exception as e:
        print(f"Error creating connection: {e}")

def push_uctv_config(token):
    """Pushes the registration token and config to the UCTV Controller via SSH."""
    if not UCTV_CONTROLLER_IP:
        return
        
    print(f"\n--- Step 2/4: Register UCTV Controller via SSH ---")
    print(f"Pushing configuration to UCTV Controller ({UCTV_CONTROLLER_IP})...")
    
    config_content = f"""Registration:
  groupName: {FM_GROUP}
  subGroupName: {FM_SUBGROUP}
  token: {token}
  remoteAddress: {FM_IP}
  remotePort: 443
"""
    
    ssh_cmd = [
        "ssh", "-i", "./lab_key.pem", "-o", "StrictHostKeyChecking=no",
        f"peter@{UCTV_CONTROLLER_IP}",
        "sudo bash -c 'cat > /etc/gigamon-cloud.conf && systemctl restart uctv-cntlr'"
    ]
    
    print(f"  Attempting SSH connection to peter@{UCTV_CONTROLLER_IP}...")
    try:
        process = subprocess.run(
            ssh_cmd, 
            input=config_content, 
            text=True, 
            capture_output=True,
            check=True
        )
        print("  [SUCCESS] Successfully wrote /etc/gigamon-cloud.conf and restarted uctv-cntlr service.")
    except FileNotFoundError:
        print("  [ERROR] 'ssh' command not found on PATH. Ensure SSH client is installed and accessible.")
    except subprocess.CalledProcessError as e:
        print(f"  [ERROR] Failed to push config via SSH.")
        print(f"  Ensure 'lab_key.pem' is in the current directory.")
        if e.stderr:
            print(f"  SSH Error: {e.stderr.strip()}")
    except Exception as e:
        print(f"  [ERROR] Unhandled exception during SSH: {e}")

def push_vseries_config(token):
    """Pushes the registration token and config to the vSeries node via SSH."""
    if not VSERIES_IP:
        return
        
    print(f"\n--- Step 3/4: Register vSeries Node via SSH ---")
    print(f"Pushing configuration to vSeries node ({VSERIES_IP})...")
    
    config_content = f"""Registration:
  groupName: {FM_GROUP}
  subGroupName: {FM_SUBGROUP}
  token: {token}
  remoteAddress: {FM_IP}
  remotePort: 443
"""
    
    # Run SSH natively and pass the config via stdin to avoid quoting issues
    ssh_cmd = [
        "ssh", "-i", "./lab_key.pem", "-o", "StrictHostKeyChecking=no",
        f"peter@{VSERIES_IP}",
        "sudo bash -c 'cat > /etc/gigamon-cloud.conf && systemctl restart vseries-node'"
    ]
    
    print(f"  Attempting SSH connection to peter@{VSERIES_IP}...")
    try:
        process = subprocess.run(
            ssh_cmd, 
            input=config_content, 
            text=True, 
            capture_output=True,
            check=True
        )
        print("  [SUCCESS] Successfully wrote /etc/gigamon-cloud.conf and restarted vseries-node service.")
    except FileNotFoundError:
        print("  [ERROR] 'ssh' command not found on PATH. Ensure SSH client is installed and accessible.")
    except subprocess.CalledProcessError as e:
        print(f"  [ERROR] Failed to push config via SSH.")
        print(f"  Ensure 'lab_key.pem' is in the current directory.")
        if e.stderr:
            print(f"  SSH Error: {e.stderr.strip()}")
    except Exception as e:
        print(f"  [ERROR] Unhandled exception during SSH: {e}")

def restart_ubuntu_agents():
    """Restarts the UCTV agent on the production Ubuntu VMs via SSH."""
    print(f"\n--- Step 4/4: Restart Ubuntu UCTV Agents via SSH ---")
    for ip, name in [(PROD1_IP, "prod-ubuntu-1"), (PROD2_IP, "prod-ubuntu-2")]:
        if not ip:
            continue
        print(f"Restarting uctv agent daemon on {name} ({ip})...")
        ssh_cmd = [
            "ssh", "-i", "./lab_key.pem", "-o", "StrictHostKeyChecking=no",
            f"peter@{ip}",
            "sudo systemctl restart uctv"
        ]
        try:
            subprocess.run(ssh_cmd, capture_output=True, check=True)
            print(f"  [SUCCESS] Successfully restarted uctv service on {name}.")
        except Exception as e:
            print(f"  [WARNING] Could not restart agent on {name}. It may restart automatically later via timer.")

def check_service_status(ip, service_name, user="peter"):
    """Checks if a systemd service is active on a remote VM via SSH."""
    if not ip:
        return "SKIPPED"
    
    cmd = [
        "ssh", "-i", "./lab_key.pem", "-o", "StrictHostKeyChecking=no", "-o", "ConnectTimeout=5",
        f"{user}@{ip}",
        f"systemctl is-active {service_name}"
    ]
    
    try:
        result = subprocess.run(cmd, capture_output=True, text=True)
        status = result.stdout.strip()
        if result.returncode == 0 and status == "active":
            return "UP"
        return f"DOWN ({status})" if status else "DOWN"
    except Exception:
        return "UNREACHABLE"

def check_lab_status():
    """Performs a quick health check of the lab environment."""
    print("\n" + "="*60)
    print("   Azure Lab Status Check")
    print("="*60)
    
    # 1. FM Status
    print(f"[-] GigaVUE-FM ({FM_IP}): ".ljust(40), end="", flush=True)
    try:
        # Just check if API responds (even 401 is fine, means it's up)
        resp = requests.get(f"{FM_URL}/api/v1.3/user", verify=False, timeout=3, auth=("dummy", "dummy"))
        if resp.status_code in [200, 401, 403]:
             print("UP (API Ready)")
        else:
             print(f"DOWN (HTTP {resp.status_code})")
    except Exception:
        print("UNREACHABLE")

    # 2. UCT-V Controller
    print(f"[-] UCT-V Controller ({UCTV_CONTROLLER_IP}): ".ljust(40), end="", flush=True)
    print(check_service_status(UCTV_CONTROLLER_IP, "uctv-cntlr"))

    # 3. vSeries Node
    print(f"[-] vSeries Node ({VSERIES_IP}): ".ljust(40), end="", flush=True)
    print(check_service_status(VSERIES_IP, "vseries-node"))

    # 4. Prod VMs
    print(f"[-] Prod VM 1 ({PROD1_IP}): ".ljust(40), end="", flush=True)
    print(check_service_status(PROD1_IP, "uctv"))
    
    print(f"[-] Prod VM 2 ({PROD2_IP}): ".ljust(40), end="", flush=True)
    print(check_service_status(PROD2_IP, "uctv"))
    print("="*60 + "\n")

def main():
    print("---------------------------------------------------------")
    print("   Gigamon V Series - FM API Configuration")
    print("---------------------------------------------------------")

    if not check_fm_accessible():
        print("FM is not reachable. Is the VM running?")
        sys.exit(1)

    print("\n" + "="*60)
    print("ACTION REQUIRED: Generate and Upload FM API Token")
    print("="*60)
    print(f"1. Log into GigaVUE-FM at {FM_URL}")
    print("   (User: admin, Password: <your_password>)")
    print("2. Go to Administration > User Management > Tokens > Current User Tokens")
    print("3. Click 'New Token', set expiry to max (105 days), and click OK.")
    print("4. After creating the token, tick the tickbox next to it and then click 'Copy'. The token is NOT displayed on screen but is automatically copied to your clipboard.")
    print("5. Run the following command in a separate terminal to upload it to Azure Key Vault:")
    print(f"\n   az keyvault secret set --vault-name \"{KEY_VAULT_NAME}\" --name \"{FM_TOKEN_SECRET_NAME}\" --value \"<PASTE_TOKEN_HERE>\"\n")
