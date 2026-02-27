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
    try:
        # Check if we should stream output
        process = subprocess.Popen(
            command,
            stdout=sys.stdout,
            stderr=sys.stderr,
            universal_newlines=True
        )
        process.communicate()
        
        if process.returncode != 0:
            print(f"\033[91mError: '{' '.join(command)}' failed with exit code {process.returncode}\033[0m")
            return False
        return True
    except Exception as e:
        print(f"\033[91mFailed to execute {command[0]}: {e}\033[0m")
        return False

def main():
    start_time = datetime.now()
    print_header(f"Starting Azure Lab Deployment\n Start Time: {start_time.strftime('%Y-%m-%d %H:%M:%S')}")

    success = False
    try:
        # 1. Terraform Init
        if not run_command(["terraform", "init"], "1/5: Initialize Terraform"):
            raise Exception("Terraform init failed")

        # 2. Terraform Plan
        if not run_command(["terraform", "plan", "-out=tfplan"], "2/5: Plan Terraform"):
             raise Exception("Terraform plan failed")

        # 3. Terraform Apply
        if not run_command(["terraform", "apply", "tfplan"], "3/5: Apply Terraform"):
             raise Exception("Terraform apply failed")

        # 4. Set up Python Environment
        venv_path = os.path.join(".", "scripts", ".venv")
        print(f"\n\033[93m>>> 4/5: Setting up Python virtual environment in {venv_path}...\033[0m")
        if not os.path.exists(venv_path):
            if not run_command([sys.executable, "-m", "venv", venv_path], "Create venv"):
                raise Exception("Failed to create virtual environment")

        # Determine path to pip and python based on OS
        if os.name == 'nt':  # Windows
            pip_exe = os.path.join(venv_path, "Scripts", "pip.exe")
            python_exe = os.path.join(venv_path, "Scripts", "python.exe")
        else:  # Unix/macOS
            pip_exe = os.path.join(venv_path, "bin", "pip")
            python_exe = os.path.join(venv_path, "bin", "python")

        requirements_file = os.path.join(".", "scripts", "requirements.txt")
        if not run_command([pip_exe, "install", "-r", requirements_file], "Install requirements"):
            raise Exception("Failed to install Python requirements")

        # 5. Run configure_lab.py
        script_file = os.path.join(".", "scripts", "configure_lab.py")
        if not os.path.exists(script_file):
             raise Exception(f"{script_file} was not found. Did terraform generate it?")
        
        if not run_command([python_exe, script_file], "5/5: Run configure_lab.py"):
            raise Exception("configure_lab.py script failed")

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
