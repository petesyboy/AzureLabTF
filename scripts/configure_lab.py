import argparse
import time
import sys
import os
import requests
import paramiko
import time

# Disable SSL warnings
import urllib3
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

def check_fm_ready(fm_ip, retries=60, delay=10):
    url = f"https://{fm_ip}/api/v1.2/system"
    print(f"Waiting for FM at {fm_ip} to be ready...")
    for i in range(retries):
        try:
            response = requests.get(url, verify=False, timeout=5)
            if response.status_code in [200, 401]:
                print(f"FM is ready! (Status: {response.status_code})")
                return True
        except requests.exceptions.RequestException:
            pass
        print(f"FM not ready yet (Attempt {i+1}/{retries}). Waiting {delay}s...")
        time.sleep(delay)
    return False

def get_fm_token(fm_ip, password):
    url = f"https://{fm_ip}/api/v1.2/authen"
    payload = {"username": "admin", "password": password}
    try:
        response = requests.post(url, json=payload, verify=False, timeout=10)
        response.raise_for_status()
        print("Successfully authenticated with FM.")
        return response.json().get('token')
    except Exception as e:
        print(f"Failed to authenticate with FM: {e}")
        sys.exit(1)

def create_monitoring_domain(fm_ip, token, group_name, subgroup_name):
    print(f"Creating Monitoring Domain '{group_name}' and Connection '{subgroup_name}' (Mock)...")
    # Placeholder for actual API call
    pass

def update_vm_config(ip, username, key_path, fm_ip, group_name, subgroup_name, token):
    print(f"Configuring VM at {ip}...")
    key = paramiko.RSAKey.from_private_key_file(key_path)
    client = paramiko.SSHClient()
    client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    
    try:
        client.connect(hostname=ip, username=username, pkey=key, timeout=10)
        
        config_content = f"""Registration:
    groupName: {group_name}
    subGroupName: {subgroup_name}
    token: {token}
    remoteIP: {fm_ip}
    remotePort: 443
"""
        cmd = f"sudo bash -c 'cat > /etc/gigamon-cloud.conf <<EOF\n{config_content}\nEOF'"
        stdin, stdout, stderr = client.exec_command(cmd)
        if stdout.channel.recv_exit_status() != 0:
            print(f"  Error writing config: {stderr.read().decode()}")
        else:
            print("  Config written successfully.")
            client.exec_command("sudo systemctl restart uctv-agent || true")
        client.close()
    except Exception as e:
        print(f"  Failed to configure VM {ip}: {e}")

import platform
import subprocess

def ping_vm(ip, description):
    """
    Pings a VM and returns True if successful, False otherwise.
    Uses system ping command.
    """
    print(f"Pinging {description} at {ip}...")
    
    # Determine the ping command based on the OS
    param = '-n' if platform.system().lower() == 'windows' else '-c'
    command = ['ping', param, '1', ip]
    
    try:
        # Run the ping command
        # stdout=subprocess.DEVNULL suppresses the output of the ping command itself
        result = subprocess.run(command, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        
        if result.returncode == 0:
            print(f"  [PASS] {description} is reachable.")
            return True
        else:
            print(f"  [FAIL] {description} is NOT reachable.")
            return False
    except Exception as e:
        print(f"  [ERROR] Failed to execute ping: {e}")
        return False

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--fm-ip", required=True)
    parser.add_argument("--uctv-ip", required=True)
    parser.add_argument("--uctv-public-ip", required=True)
    parser.add_argument("--key-path", required=True)
    parser.add_argument("--fm-group", required=True)
    parser.add_argument("--fm-subgroup", required=True)
    parser.add_argument("--fm-password", required=True)
    parser.add_argument("--prod-ips", required=True)
    parser.add_argument("--vseries-public-ip", required=True)
    parser.add_argument("--tool-public-ip", required=True)
    parser.add_argument("--username", default="azureuser")
    args = parser.parse_args()
    
    if not check_fm_ready(args.fm_ip):
        sys.exit(1)
        
    token = get_fm_token(args.fm_ip, args.fm_password)
    create_monitoring_domain(args.fm_ip, token, args.fm_group, args.fm_subgroup)
    
    # Configure UCT-V Controller (via public IP)
    update_vm_config(args.uctv_public_ip, args.username, args.key_path, args.fm_ip, args.fm_group, args.fm_subgroup, token)
    
    # Configure Prod VMs collected into a list for iteration
    prod_vm_ips = [ip for ip in args.prod_ips.split(',') if ip]
    for i, ip in enumerate(prod_vm_ips):
        update_vm_config(ip, args.username, args.key_path, args.fm_ip, args.fm_group, args.fm_subgroup, token)
            
    print("\n------------------------------------------------------------")
    print("Verifying Connectivity (Ping Check)")
    print("------------------------------------------------------------")
    
    # List of VMs to ping: (IP, Description)
    vms_to_ping = [
        (args.fm_ip, "GigaVUE-FM"),
        (args.uctv_public_ip, "UCT-V Controller"),
        (args.vseries_public_ip, "vSeries Node"),
        (args.tool_public_ip, "Tool VM")
    ]
    
    # Add Prod VMs to the list
    for i, ip in enumerate(prod_vm_ips):
        vms_to_ping.append((ip, f"Prod VM {i+1}"))
        
    # Execute pings
    passed_count = 0
    for ip, desc in vms_to_ping:
        if ping_vm(ip, desc):
            passed_count += 1
            
    print("------------------------------------------------------------")
    print(f"Ping Check Complete: {passed_count}/{len(vms_to_ping)} VMs reachable.")
    print("------------------------------------------------------------")
    
    print("\nLab Configuration Complete!")

if __name__ == "__main__":
    main()
