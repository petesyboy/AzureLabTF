#!/usr/bin/env python3

import os
import sys
import time
import argparse
import json
import subprocess
import shutil
from datetime import datetime, timedelta
import stat
import re

def print_header(text, color="cyan"):
    colors = {
        "cyan": "\033[96m",
        "yellow": "\033[93m",
        "green": "\033[92m",
        "red": "\033[91m",
        "reset": "\033[0m"
    }
    c = colors.get(color, colors["reset"])
    print(f"{c}======================================================={colors['reset']}")
    print(f"{c} {text}{colors['reset']}")
    print(f"{c}======================================================={colors['reset']}")

def run_command(command, step_name, verbose=False):
    print(f"\n\033[93m>>> {step_name}: Running '{' '.join(command)}'...\033[0m")
    env = os.environ.copy()
    env["PYTHON_KEYRING_BACKEND"] = "keyring.backends.null.Keyring"
    env["PYTHONUNBUFFERED"] = "1"
    env["PYTHONWARNINGS"] = "ignore"
    
    # If verbose is true, we let output stream to console. 
    # Otherwise, we capture it to show only on error.
    stdout_dest = None if verbose else subprocess.PIPE
    stderr_dest = None if verbose else subprocess.PIPE

    try:
        result = subprocess.run(command, env=env, stdout=stdout_dest, stderr=stderr_dest, text=True)
        if result.returncode != 0:
            print(f"\033[91mError: '{' '.join(command)}' failed with exit code {result.returncode}\033[0m")
            if not verbose:
                print(f"\033[91mSTDOUT:\033[0m\n{result.stdout}")
                print(f"\033[91mSTDERR:\033[0m\n{result.stderr}")
            return False
        return True
    except Exception as e:
        print(f"\033[91mFailed to execute {command[0]}: {e}\033[0m")
        return False

def wait_for_cloud_init(ip, user, key_file, vm_name):
    print(f"Waiting for cloud-init on {vm_name} ({ip})... (Check /var/log/cloud-init-output.log on VM for details)")
    ssh_cmd = [
        "ssh", "-i", key_file, "-o", "StrictHostKeyChecking=no", "-o", "UserKnownHostsFile=/dev/null",
        "-o", "ConnectTimeout=10",
        f"{user}@{ip}",
        "cloud-init status --wait"
    ]
    
    max_retries = 10
    for attempt in range(max_retries):
        try:
            result = subprocess.run(ssh_cmd, capture_output=True, text=True)
            stdout = result.stdout.strip()
            stderr = result.stderr.strip()
            
            # If we don't get the 'status: ' string, SSH probably failed to connect or authenticate
            if "status:" not in stdout:
                print(f"  ... Still waiting for SSH/cloud-init on {vm_name} (Attempt {attempt+1}/{max_retries})")
                time.sleep(15)
                continue

            if "status: done" in stdout:
                print(f"\033[92m  [SUCCESS] cloud-init finished successfully.\033[0m")
                return True
            elif "status: error" in stdout or "status: degraded" in stdout:
                print(f"\033[91m  [ERROR] cloud-init failed or degraded. Output:\n    {stdout}\033[0m")
                return False
            else:
                print(f"\033[93m  [WARNING] cloud-init returned unexpected status (Code: {result.returncode}).\n    Output: {stdout}\n    Error: {stderr}\033[0m")
                return False
        except Exception as e:
            print(f"\033[91m  [ERROR] Failed to execute SSH check: {e}\033[0m")
            return False
            
    print(f"\033[91m  [ERROR] Could not verify cloud-init on {vm_name} after {max_retries} attempts.\033[0m")
    return False

def manage_vm_power_states(az_cmd, rg_name):
    """Checks VM power states and offers to start them to avoid Terraform 409 conflicts."""
    print(f"\n\033[93m>>> Checking VM power states in Resource Group '{rg_name}'...\033[0m")
    try:
        # Query Azure for VM names and their power state
        cmd = [
            az_cmd, "vm", "list", 
            "-g", rg_name, 
            "-d", 
            "--query", "[].{name:name, state:powerState}", 
            "-o", "json"
        ]
        result = subprocess.run(cmd, capture_output=True, text=True)
        if result.returncode != 0:
            return # RG likely doesn't exist yet
            
        vms = json.loads(result.stdout)
        stopped_vms = [v['name'] for v in vms if v.get('state') and 'running' not in v['state'].lower()]
        
        if stopped_vms:
            print(f"\033[93m[!] The following VMs are NOT running: {', '.join(stopped_vms)}\033[0m")
            print("Terraform may fail with a 409 Conflict if it tries to modify deallocated VMs.")
            if input("Would you like to power them on now? (y/n): ").lower() == 'y':
                for vm in stopped_vms:
                    print(f"Starting {vm}...")
                    subprocess.run([az_cmd, "vm", "start", "-g", rg_name, "-n", vm, "--no-wait"], check=False)
                print("\033[92m[SUCCESS] Start commands issued. Waiting 10s for Azure to process...\033[0m")
                time.sleep(10)
    except Exception as e:
        print(f"\033[91mWarning: Could not verify VM status: {e}\033[0m")

def get_gigamon_version():
    """Parses variables.tf to find the default gigamon_version."""
    try:
        with open("variables.tf", "r") as f:
            content = f.read()
            match = re.search(r'variable\s+"gigamon_version"\s+{[^}]+default\s+=\s+"([^"]+)"', content)
            if match:
                return match.group(1)
    except Exception:
        pass
    return "6.13" # Fallback default

def check_marketplace_terms(az_cmd, version, verbose=False):
    """Checks if Marketplace terms are accepted for Gigamon images and offers to accept them."""
    sku_code = version.replace(".", "") + "00"
    publisher = "gigamon-inc"
    offer = "gigamon-gigavue-cloud-suite-v2"
    plans = [
        f"gfm-azure-v{sku_code}",
        f"uctv-cntlr-v{sku_code}",
        f"vseries-node-v{sku_code}"
    ]

    print(f"\n\033[93m>>> Checking Azure Marketplace terms for version {version}...\033[0m")
    for plan in plans:
        try:
            # Check current status
            cmd = [az_cmd, "vm", "image", "terms", "show", "--publisher", publisher, "--offer", offer, "--plan", plan, "-o", "json"]
            result = subprocess.run(cmd, capture_output=True, text=True)
            
            accepted = False
            if result.returncode == 0:
                terms = json.loads(result.stdout)
                accepted = terms.get("accepted", False)

            if accepted:
                print(f"\033[92m  [OK] Terms already accepted for: {plan}\033[0m")
            else:
                print(f"\033[93m  [!] Terms NOT accepted for: {plan}\033[0m")
                user_input = input(f"      Would you like to accept terms for '{plan}' now? (y/n): ").lower()
                if user_input == 'y':
                    accept_cmd = [az_cmd, "vm", "image", "terms", "accept", "--publisher", publisher, "--offer", offer, "--plan", plan]
                    if run_command(accept_cmd, f"Accepting terms for {plan}", verbose):
                        print(f"\033[92m      [SUCCESS] Terms accepted.\033[0m")
                    else:
                        print(f"\033[91m      [ERROR] Failed to accept terms for {plan}.\033[0m")
        except Exception as e:
            print(f"\033[91m  [ERROR] Could not verify terms for {plan}: {e}\033[0m")

def purge_deleted_keyvaults(az_cmd, location):
    """Checks for soft-deleted Key Vaults and purges them to avoid naming conflicts."""
    print(f"\n\033[93m>>> Checking for soft-deleted Key Vaults in {location}...\033[0m")
    try:
        cmd = [az_cmd, "keyvault", "list-deleted", "--query", "[].name", "-o", "json"]
        result = subprocess.run(cmd, capture_output=True, text=True)
        if result.returncode == 0:
            deleted_kvs = json.loads(result.stdout)
            if deleted_kvs:
                print(f"\033[93m[!] Found soft-deleted Key Vaults: {', '.join(deleted_kvs)}\033[0m")
                if input("Would you like to purge them to avoid naming conflicts? (y/n): ").lower() == 'y':
                    for kv in deleted_kvs:
                        print(f"Purging {kv}...")
                        subprocess.run([az_cmd, "keyvault", "purge", "--name", kv, "--location", location, "--no-wait"], check=False)
                    print("\033[92m[SUCCESS] Purge commands issued.\033[0m")
    except Exception as e:
        print(f"Note: Could not check for deleted Key Vaults: {e}")

def main():
    parser = argparse.ArgumentParser(description="Gigamon Azure Lab Orchestrator")
    parser.add_argument("--destroy", action="store_true", help="Tear down the infrastructure")
    parser.add_argument("--debug", action="store_true", help="Stream all command output to console")
    args = parser.parse_args()

    is_destroy = args.destroy
    is_debug = args.debug
    gigamon_version = get_gigamon_version()

    start_time = datetime.now()
    mode = "Destruction" if is_destroy else "Deployment"
    print_header(f"Gigamon Azure Lab {mode}\n Suite Version: {gigamon_version}\n Start Time: {start_time.strftime('%Y-%m-%d %H:%M:%S')}")

    success = False
    try:
        # 0. Pre-flight: Check Azure Login
        print(f"\n\033[93m>>> 0/6: Checking Azure CLI Authentication...\033[0m")
        
        # Resolve 'az' command
        az_cmd = shutil.which("az") or ("az.cmd" if os.name == 'nt' else "az")

        # Pre-emptive Key Vault Cleanup (to free up names from previous failed/aborted runs)
        try:
            purge_deleted_keyvaults(az_cmd, "uksouth")
        except:
            pass

        try:
            subprocess.check_output([az_cmd, "account", "show"], stderr=subprocess.DEVNULL)
            print("\033[92m[OK] Azure CLI is authenticated.\033[0m")
        except subprocess.CalledProcessError:
            raise Exception("You are not logged into Azure CLI. Please run 'az login' first.")

        if is_destroy:
            # Ensure terraform is initialized before attempting destruction
            if not os.path.exists(".terraform"):
                run_command(["terraform", "init"], "Initializing Terraform for destruction", is_debug)
                
            if run_command(["terraform", "destroy", "-auto-approve"], "Tearing down infrastructure", is_debug):
                print("\n\033[93m>>> Performing post-destroy Key Vault purge (optional)...\033[0m")
                purge_deleted_keyvaults(az_cmd, "uksouth")
                print_header("Lab Destroyed Successfully", "green")
                sys.exit(0)
            else:
                raise Exception("Terraform destroy failed")

        # 0b. Marketplace Terms Check
        check_marketplace_terms(az_cmd, gigamon_version, is_debug)

        # 1. Terraform Init
        if not run_command(["terraform", "init"], "1/6: Initialize Terraform", is_debug):
            raise Exception("Terraform init failed")

        # 2. Terraform Plan
        if not run_command(["terraform", "plan", "-out=tfplan"], "2/6: Plan Terraform", is_debug):
             raise Exception("Terraform plan failed")

        # Pre-Apply Power State Check
        try:
            # Try to get RG name from existing state to check power states before apply
            rg_name_pre = subprocess.check_output(["terraform", "output", "-raw", "resource_group_name"], text=True, stderr=subprocess.DEVNULL).strip()
            if rg_name_pre:
                manage_vm_power_states(az_cmd, rg_name_pre)
        except:
            pass

        # 3. Terraform Apply
        if not run_command(["terraform", "apply", "tfplan"], "3/6: Apply Terraform", is_debug):
             raise Exception("Terraform apply failed")

        # 4. Set up Python Environment
        venv_path = os.path.join(".", "scripts", ".venv")
        print(f"\n\033[93m>>> 4/6: Setting up Python virtual environment in {venv_path}...\033[0m")

        # Determine path to python based on OS
        if os.name == 'nt':  # Windows
            python_exe = os.path.join(venv_path, "Scripts", "python.exe")
        else:  # Unix/macOS
            python_exe = os.path.join(venv_path, "bin", "python")

        # Check if venv exists and is valid (handles cross-OS sync issues via OneDrive)
        if os.path.exists(venv_path):
            recreate = False
            
            # 1. Check for cross-OS directory structure (bin vs Scripts)
            if os.name == 'nt' and os.path.exists(os.path.join(venv_path, "bin")) and not os.path.exists(os.path.join(venv_path, "Scripts")):
                 recreate = True
            
            # 2. Check executable and functionality
            if not recreate:
                if not os.path.exists(python_exe):
                    recreate = True
                else:
                    try:
                        subprocess.check_call([python_exe, "--version"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                    except Exception:
                        recreate = True
            
            if recreate:
                print(f"\033[93mDetected invalid or cross-OS virtual environment. Recreating...\033[0m")
                # Robust deletion for Windows/OneDrive
                for attempt in range(3):
                    try:
                        if os.path.exists(venv_path):
                            def on_rm_error(func, path, exc_info):
                                try:
                                    os.chmod(path, stat.S_IWRITE)
                                    func(path)
                                except Exception:
                                    pass
                            shutil.rmtree(venv_path, onerror=on_rm_error)
                        break
                    except Exception:
                        if attempt < 2:
                            time.sleep(2)
                        elif os.name == 'nt':
                            subprocess.run(f'rmdir /S /Q "{venv_path}"', shell=True, check=False)
                        else:
                            subprocess.run(f'rm -rf "{venv_path}"', shell=True, check=False)
                
                time.sleep(2) # Wait for filesystem to settle

        if not os.path.exists(venv_path):
            if not run_command([sys.executable, "-m", "venv", venv_path], "Create venv"):
                raise Exception("Failed to create virtual environment")

        # Upgrade pip using python -m pip (more reliable than the pip executable)
        # We use --no-cache-dir to avoid issues with synced CloudStorage folders.
        run_command([python_exe, "-m", "pip", "install", "--upgrade", "pip", "--no-input", "--no-cache-dir"], "Upgrade pip")

        requirements_file = os.path.join(".", "scripts", "requirements.txt")
        if not run_command([python_exe, "-m", "pip", "install", "-r", requirements_file, "--no-input", "--disable-pip-version-check", "--no-cache-dir"], "Install requirements"):
            raise Exception("Failed to install Python requirements")

        # Get Key Vault details from Terraform
        print("\n\033[93m>>> Fetching deployment details from Terraform...\033[0m")
        try:
            outputs_json = subprocess.check_output(["terraform", "output", "-json"], text=True)
            outputs = json.loads(outputs_json)
            
            kv_name = outputs['key_vault_name']['value']
            secret_name = outputs['fm_token_secret_name']['value']
            fm_ip = outputs['fm_public_ip']['value']
            rg_name = outputs['resource_group_name']['value']
            location = outputs['location']['value']
            
            admin_username = outputs.get('admin_username', {}).get('value')
            lab_key_file = outputs.get('lab_key_file', {}).get('value')
            prod1_ip = outputs.get('prod1_public_ip', {}).get('value')
            prod2_ip = outputs.get('prod2_public_ip', {}).get('value')
            tool_vm_ip = outputs.get('tool_vm_public_ip', {}).get('value')
        except (subprocess.CalledProcessError, KeyError):
            raise Exception("Failed to fetch Terraform outputs. Ensure 'outputs.tf' exists and defines key_vault_name, fm_token_secret_name, fm_public_ip, resource_group_name, and location.")

        # Upload UCTV Files to Azure Storage
        try:
            print("\n\033[93m>>> Checking for UCTV files and Storage Account...\033[0m")

            # These should now always exist in TF output
            sa_name = outputs['storage_account_name']['value']
            sa_container = outputs['storage_container_name']['value']
            
            # 3. Check Local Files
            uctv_source_dir = os.path.join(".", "UCTV-files")
            if not os.path.exists(uctv_source_dir):
                os.makedirs(uctv_source_dir)
            
            while True:
                if any(os.path.isfile(os.path.join(uctv_source_dir, f)) for f in os.listdir(uctv_source_dir)):
                    break
                print(f"\033[91m[!] No files found in '{uctv_source_dir}'.\033[0m")
                print("Please copy the UCTV agent files (e.g., .deb, .rpm) into this directory now.")
                input("Press Enter once files are present...")
            
            print(f"Target Storage Account: {sa_name}")
            print(f"Target Container:       {sa_container}")
            
            # 4. Ensure Storage Account Exists
            print(f"Checking existence of Storage Account '{sa_name}'...")
            check_sa = subprocess.run([az_cmd, "storage", "account", "show", "--name", sa_name, "--resource-group", rg_name], capture_output=True)
            
            if check_sa.returncode != 0:
                print(f"\033[93mStorage Account '{sa_name}' not found. Creating in {rg_name} ({location})...\033[0m")
                create_cmd = [
                    az_cmd, "storage", "account", "create",
                    "--name", sa_name,
                    "--resource-group", rg_name,
                    "--location", location,
                    "--sku", "Standard_LRS"
                ]
                if not run_command(create_cmd, "Create Storage Account", is_debug):
                    raise Exception(f"Failed to create storage account {sa_name}")
            
            # 5. Upload Files (using Key Auth for reliability)
            print("Retrieving Storage Account Key...")
            key_cmd = [az_cmd, "storage", "account", "keys", "list", "--account-name", sa_name, "--resource-group", rg_name, "--query", "[0].value", "-o", "tsv"]
            sa_key = subprocess.check_output(key_cmd, text=True).strip()
            
            # Create container if needed (idempotent-ish via CLI or ignore error)
            subprocess.run([az_cmd, "storage", "container", "create", "--name", sa_container, "--account-name", sa_name, "--account-key", sa_key], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

            upload_cmd = [
                az_cmd, "storage", "blob", "upload-batch",
                "--account-name", sa_name,
                "--account-key", sa_key,
                "--destination", sa_container,
                "--source", uctv_source_dir,
                "--overwrite", "true"
            ]
            
            if run_command(upload_cmd, "Upload UCTV Files", is_debug):
                print("\033[92m[SUCCESS] Files uploaded to Azure Storage.\033[0m")
            else:
                raise Exception("Failed to upload UCTV files.")

        except Exception as e:
            print(f"\033[91mError during storage/upload operations: {e}\033[0m")
            raise e

        # Wait for cloud-init on Standard Ubuntu VMs
        if admin_username and lab_key_file:
            print("\n\033[93m>>> Validating SSH Key and waiting for cloud-init...\033[0m")
            if not os.path.exists(lab_key_file):
                print(f"\033[91m[ERROR] SSH Key file not found at {lab_key_file}\033[0m")
            else:
                # Auto-fix permissions on Unix-like systems
                if os.name != 'nt':
                    os.chmod(lab_key_file, 0o400)
            vms_to_check = [("Tool VM", tool_vm_ip), ("Production VM 1", prod1_ip), ("Production VM 2", prod2_ip)]
            for name, ip in vms_to_check:
                if ip:
                    wait_for_cloud_init(ip, admin_username, lab_key_file, name)

        # Manual Intervention Step
        print_header("ACTION REQUIRED", "yellow")
        print(f"1. Open GigaVUE-FM: https://{fm_ip}")
        print("   (Credentials: admin / admin123A!!)")
        print("   IMPORTANT: You MUST change the admin password in the UI now.")
        print("2. Generate an API Token (Administration > User Management > Tokens > New Token).")
        print("3. Upload the token to Key Vault:")
        print("\n   Bash:")
        print(f"   az keyvault secret set --vault-name \"{kv_name}\" --name \"{secret_name}\" --value \"<YOUR_TOKEN>\"")
        print("\n   PowerShell:")
        print(f"   $KV_NAME = \"{kv_name}\"")
        print(f"   $SECRET_NAME = \"{secret_name}\"")
        print(f"   az keyvault secret set --vault-name $KV_NAME --name $SECRET_NAME --value \"<YOUR_TOKEN>\"\n")
        
        # Verification Loop
        while True:
            verify = input("Check Key Vault for token now? (y/n/skip): ").lower()
            if verify == 'y':
                check_cmd = [az_cmd, "keyvault", "secret", "show", "--vault-name", kv_name, "--name", secret_name]
                result = subprocess.run(check_cmd, capture_output=True)
                if result.returncode == 0:
                    print("\033[92m[SUCCESS] Token found in Key Vault!\033[0m")
                    break
                else:
                    print("\033[91m[ERROR] Token not found or Access Denied. (RBAC may still be propagating).\033[0m")
            elif verify == 'skip':
                break

        input("\nOnce the token is uploaded to Key Vault, press Enter to continue with configuration...")

        # 5. Run configure_lab.py
        script_file = os.path.join(".", "scripts", "configure_lab.py")
        if not os.path.exists(script_file):
             raise Exception(f"{script_file} was not found. Did terraform generate it?")
        
        if not run_command([python_exe, script_file], "5/6: Run configure_lab.py", is_debug):
            raise Exception("configure_lab.py script failed")

        # 6. Run status check
        if not run_command([python_exe, script_file, "--status"], "6/6: Run Post-Deployment Status Check", is_debug):
            # Don't fail the whole build, just warn the user.
            print("\033[93mWarning: Status check reported issues. The lab might be partially functional.\033[0m")

        success = True

    except Exception as e:
         print_header(f"Deployment failed: {e}", "red")
         success = False

    end_time = datetime.now()
    elapsed = end_time - start_time
    
    # Format elapsed time
    hours, remainder = divmod(elapsed.total_seconds(), 3600)
    minutes, seconds = divmod(remainder, 60)

    if success:
        print_header("Lab Deployment Completed SUCCESSFULLY!", "green")
        
        print("\n\033[93m>>> Connection Details (SSH):\033[0m")
        try:
            ssh_targets = [
                ("GigaVUE-FM", "ssh_fm"),
                ("UCT-V Cntlr", "ssh_uctv"),
                ("vSeries Node", "ssh_vseries"),
                ("Tool VM", "ssh_tool_vm"),
                ("Prod VM 1", "ssh_prod1"),
                ("Prod VM 2", "ssh_prod2")
            ]
            for label, out_name in ssh_targets:
                try:
                    cmd = subprocess.check_output(["terraform", "output", "-raw", out_name], stderr=subprocess.DEVNULL, text=True).strip()
                    print(f"  {label.ljust(15)}: {cmd}")
                except:
                    pass

            print("\n\033[93m>>> Logs & Troubleshooting:\033[0m")
            print("  Use these logs on the VMs to debug registration or configuration issues:")
            print("  - Gigamon Bootstrap:   /var/log/gigamon-bootstrap.log  (Token fetch, UCT-V install)")
            print("  - Cloud-Init Output:   /var/log/cloud-init-output.log  (Package install, runcmd logs)")
            print("\n  Example to tail logs live:")
            print(f"    ssh -i {lab_key_file} {admin_username}@{prod1_ip} 'tail -f /var/log/gigamon-bootstrap.log'")

        except Exception:
            pass
    else:
        print_header("Lab Deployment FAILED!", "red")

    print(f"\033[96m Start Time:         {start_time.strftime('%Y-%m-%d %H:%M:%S')}")
    print(f" End Time:           {end_time.strftime('%Y-%m-%d %H:%M:%S')}")
    print(f" Total Elapsed Time: {int(hours):02d}h {int(minutes):02d}m {int(seconds):02d}s")
    print(f"=======================================================\033[0m")

    if not success:
        sys.exit(1)

if __name__ == "__main__":
    main()
