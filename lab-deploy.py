#!/usr/bin/env python3

import os
import sys
import time
import subprocess
import shutil
from datetime import datetime, timedelta
import stat

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

def run_command(command, step_name):
    print(f"\n\033[93m>>> {step_name}: Running '{' '.join(command)}'...\033[0m")
    # Disable keyring to prevent macOS hangs during pip operations
    # and ensure output is unbuffered.
    env = os.environ.copy()
    env["PYTHON_KEYRING_BACKEND"] = "keyring.backends.null.Keyring"
    env["PYTHONUNBUFFERED"] = "1"
    try:
        result = subprocess.run(
            command,
            check=False,
            env=env
        )
        if result.returncode != 0:
            print(f"\033[91mError: '{' '.join(command)}' failed with exit code {result.returncode}\033[0m")
            return False
        return True
    except Exception as e:
        print(f"\033[91mFailed to execute {command[0]}: {e}\033[0m")
        return False

def main():
    start_time = datetime.now()
    print_header(f"Gigamon Azure Lab Deployment\n Start Time: {start_time.strftime('%Y-%m-%d %H:%M:%S')}")

    success = False
    try:
        # 0. Pre-flight: Check Azure Login
        print("\n\033[93m>>> 0/6: Checking Azure CLI Authentication...\033[0m")
        
        # Version Warning
        print("\033[91m" + "!"*70)
        print("  WARNING: Deploying Gigamon Cloud Suite version 6.13")
        print("  Ensure you have accepted marketplace terms for this version.")
        print("!"*70 + "\033[0m")
        time.sleep(5)

        # Fix for Windows: Resolve 'az' to 'az.cmd' or full path
        az_cmd = shutil.which("az") or ("az.cmd" if os.name == 'nt' else "az")

        try:
            subprocess.check_output([az_cmd, "account", "show"], stderr=subprocess.DEVNULL)
            print("\033[92m[OK] Azure CLI is authenticated.\033[0m")
        except subprocess.CalledProcessError:
            raise Exception("You are not logged into Azure CLI. Please run 'az login' first.")

        # 1. Terraform Init
        if not run_command(["terraform", "init"], "1/6: Initialize Terraform"):
            raise Exception("Terraform init failed")

        # 2. Terraform Plan
        if not run_command(["terraform", "plan", "-out=tfplan"], "2/6: Plan Terraform"):
             raise Exception("Terraform plan failed")

        # 3. Terraform Apply
        if not run_command(["terraform", "apply", "tfplan"], "3/6: Apply Terraform"):
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
            kv_name = subprocess.check_output(["terraform", "output", "-raw", "key_vault_name"], text=True).strip()
            secret_name = subprocess.check_output(["terraform", "output", "-raw", "fm_token_secret_name"], text=True).strip()
            fm_ip = subprocess.check_output(["terraform", "output", "-raw", "fm_public_ip"], text=True).strip()
            rg_name = subprocess.check_output(["terraform", "output", "-raw", "resource_group_name"], text=True).strip()
            location = subprocess.check_output(["terraform", "output", "-raw", "location"], text=True).strip()
        except subprocess.CalledProcessError:
            raise Exception("Failed to fetch Terraform outputs. Ensure 'outputs.tf' exists and defines key_vault_name, fm_token_secret_name, fm_public_ip, resource_group_name, and location.")

        # Upload UCTV Files to Azure Storage
        try:
            print("\n\033[93m>>> Checking for UCTV files and Storage Account...\033[0m")

            # These should now always exist in TF output
            sa_name = subprocess.check_output(["terraform", "output", "-raw", "storage_account_name"], text=True).strip()
            sa_container = subprocess.check_output(["terraform", "output", "-raw", "storage_container_name"], text=True).strip()
            
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
                if not run_command(create_cmd, "Create Storage Account"):
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
            
            if run_command(upload_cmd, "Upload UCTV Files"):
                print("\033[92m[SUCCESS] Files uploaded to Azure Storage.\033[0m")
            else:
                raise Exception("Failed to upload UCTV files.")

        except Exception as e:
            print(f"\033[91mError during storage/upload operations: {e}\033[0m")
            raise e

        # Manual Intervention Step
        print_header("ACTION REQUIRED", "yellow")
        print(f"1. Open GigaVUE-FM: https://{fm_ip}")
        print("   (Credentials: admin / admin123A!!)")
        print("   IMPORTANT: You MUST change the admin password in the UI now.")
        print("2. Generate an API Token (Administration > User Management > Tokens > New Token).")
        print(f"3. Upload the token to Key Vault:")
        print(f"\n   az keyvault secret set --vault-name {kv_name} --name {secret_name} --value <YOUR_TOKEN>\n")
        
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
        
        if not run_command([python_exe, script_file], "5/6: Run configure_lab.py"):
            raise Exception("configure_lab.py script failed")

        # 6. Run status check
        if not run_command([python_exe, script_file, "--status"], "6/6: Run Post-Deployment Status Check"):
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
