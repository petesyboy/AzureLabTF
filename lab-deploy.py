#!/usr/bin/env python3

import os
import sys
import time
import subprocess
from datetime import datetime, timedelta

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
        try:
            subprocess.check_output(["az", "account", "show"], stderr=subprocess.DEVNULL)
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
        if not os.path.exists(venv_path):
            if not run_command([sys.executable, "-m", "venv", venv_path], "Create venv"):
                raise Exception("Failed to create virtual environment")

        # Determine path to python based on OS
        if os.name == 'nt':  # Windows
            python_exe = os.path.join(venv_path, "Scripts", "python.exe")
        else:  # Unix/macOS
            python_exe = os.path.join(venv_path, "bin", "python")

        # Upgrade pip using python -m pip (more reliable than the pip executable)
        # We use --no-cache-dir to avoid issues with synced CloudStorage folders.
        run_command([python_exe, "-m", "pip", "install", "--upgrade", "pip", "--no-input", "--no-cache-dir"], "Upgrade pip")

        requirements_file = os.path.join(".", "scripts", "requirements.txt")
        if not run_command([python_exe, "-m", "pip", "install", "-r", requirements_file, "--no-input", "--disable-pip-version-check", "--no-cache-dir"], "Install requirements"):
            raise Exception("Failed to install Python requirements")

        # Get Key Vault details from Terraform
        print("\n\033[93m>>> Fetching deployment details from Terraform...\033[0m")
        kv_name = subprocess.check_output(["terraform", "output", "-raw", "key_vault_name"], text=True).strip()
        secret_name = subprocess.check_output(["terraform", "output", "-raw", "fm_token_secret_name"], text=True).strip()
        fm_ip = subprocess.check_output(["terraform", "output", "-raw", "fm_public_ip"], text=True).strip()

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
                check_cmd = ["az", "keyvault", "secret", "show", "--vault-name", kv_name, "--name", secret_name]
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
