# Local values for cloud-init scripts and Ubuntu image details
# These are separated from main.tf to keep it more readable

locals {
  # Ubuntu image configuration
  ubuntu_publisher = "Canonical"
  ubuntu_offer     = var.ubuntu_version == "24.04" ? "ubuntu-24_04-lts" : "ubuntu-22_04-lts"
  ubuntu_sku       = "server"
  ubuntu_version   = "latest"

  # FM Cloud-Init: Minimal init.
  # Configuration is handled post-deployment via API.
  fm_cloud_init = <<-EOF
    #cloud-config
    packages: []
    runcmd:
      - echo "GigaVUE-FM 6.12 initializing..."
  EOF

  # UCT-V Controller Cloud-Init
  # We create the config file with placeholders. The Python script will populate the token.
  uctv_cloud_init = <<-EOF
    #cloud-config
    write_files:
      - path: /etc/gigamon-cloud.conf
        permissions: '0644'
        owner: root:root
        content: |
          Registration:
            groupName: ${var.fm_group_name}
            subGroupName: ${var.fm_subgroup_name}
            token: PLACEHOLDER_TOKEN
            remoteAddress: ${module.fm.public_ip}
            remotePort: 443

    runcmd:
      - echo "UCT-V Controller initialized. Waiting for configuration..."
  EOF

  # vSeries Cloud-Init
  vseries_cloud_init = <<-EOF
    #cloud-config
    write_files:
      - path: /etc/gigamon-cloud.conf
        permissions: '0644'
        owner: root:root
        content: |
          Registration:
            groupName: ${var.fm_group_name}
            subGroupName: ${var.fm_subgroup_name}
            token: PLACEHOLDER_TOKEN
            remoteAddress: ${module.fm.public_ip}
            remotePort: 443

    runcmd:
      - echo "vSeries Node initialized. Waiting for configuration..."
  EOF

  # Tool VM: ntopng + VXLAN termination
  # Deployed in Visibility Subnet
  tool_vm_cloud_init = <<-EOF
    #cloud-config
    package_upgrade: true
    packages:
      - ntopng
      - ufw
      - curl
      - jq

    write_files:
      # Script to configure VXLAN interface
      - path: /usr/local/sbin/configure-vxlan0.sh
        permissions: '0755'
        owner: root:root
        content: |
          #!/bin/bash
          set -e

          IFACE="eth0"
          VXLAN_IF="vxlan0"
          VNI="123"
          DSTPORT="4789"

          # Get the IPv4 address on the underlying interface (CIDR)
          UNDERLAY_IP=$(ip -4 addr show dev "$${IFACE}" | awk '/inet / {print $2}' | head -n1)

          echo "Configuring $${VXLAN_IF} on $${IFACE} (IP: $${UNDERLAY_IP}) with VNI $${VNI}, dstport $${DSTPORT}"

          # Create vxlan0 if it doesn't exist
          if ! ip link show "$${VXLAN_IF}" >/dev/null 2>&1; then
            ip link add "$${VXLAN_IF}" type vxlan id "$${VNI}" dev "$${IFACE}" dstport "$${DSTPORT}"
          fi

          # Bring interface up
          ip link set "$${VXLAN_IF}" up

      # Systemd service to ensure VXLAN persists across reboots
      - path: /etc/systemd/system/vxlan0.service
        permissions: '0644'
        owner: root:root
        content: |
          [Unit]
          Description=Configure vxlan0 interface (VNI 123)
          After=network-online.target
          Wants=network-online.target

          [Service]
          Type=oneshot
          ExecStart=/usr/local/sbin/configure-vxlan0.sh
          RemainAfterExit=yes

          [Install]
          WantedBy=multi-user.target

    ssh_authorized_keys:
      - ${tls_private_key.lab_key.public_key_openssh}

    runcmd:
      - systemctl daemon-reload
      - systemctl enable vxlan0.service
      - systemctl start vxlan0.service
      # Configure ntopng interfaces
      - echo "--daemon" > /etc/ntopng.conf
      - echo "-i=eth0" >> /etc/ntopng.conf
      - echo "-i=vxlan0" >> /etc/ntopng.conf
      - systemctl enable ntopng || true
      - systemctl restart ntopng || true
      # Add local firewall exception for VXLAN UDP 4789 (no-op if ufw disabled)
      - ufw allow 4789/udp || true
      # Allow ingress from UCT-V Controller and FM (if needed for tool VM logic)
      - ufw allow from ${module.uctv.private_ip} || true
      - if [ -f /var/run/reboot-required ]; then reboot; fi
  EOF

  # prod1: iperf3 + uctv-agent config placeholder
  # Removed ntopng/vxlan from here
  prod1_cloud_init = <<-EOF
    #cloud-config
    package_upgrade: true
    packages:
      - iperf3
      - curl
      - jq

    write_files:
      # UCT-V Agent Config Placeholder
      - path: /etc/gigamon-cloud.conf
        permissions: '0644'
        owner: root:root
        content: |
          Registration:
            groupName: ${var.fm_group_name}
            subGroupName: ${var.fm_subgroup_name}
            token: PLACEHOLDER_TOKEN
            remoteAddress: ${module.uctv.private_ip}
            remotePort: 8892

    ssh_authorized_keys:
      - ${tls_private_key.lab_key.public_key_openssh}

    runcmd:
      - echo "Downloading UCT-V agent from Public Blob Storage..."
      - curl -L "https://connollystorageaccount.blob.core.windows.net/uctv-agents/gigamon-gigavue-uctv-6.12.00-amd64.deb" -o /tmp/uctv-agent.deb
      - echo "Installing UCT-V agent..."
      - dpkg -i /tmp/uctv-agent.deb || apt-get install -f -y
      - echo "UCT-V agent installed."
      - if [ -f /var/run/reboot-required ]; then reboot; fi
  EOF

  # prod2: iperf3 + uctv-agent config placeholder
  prod2_cloud_init = <<-EOF
    #cloud-config
    package_upgrade: true
    packages:
      - iperf3
      - curl
      - jq

    write_files:
      # UCT-V Agent Config Placeholder
      - path: /etc/gigamon-cloud.conf
        permissions: '0644'
        owner: root:root
        content: |
          Registration:
            groupName: ${var.fm_group_name}
            subGroupName: ${var.fm_subgroup_name}
            token: PLACEHOLDER_TOKEN
            remoteAddress: ${module.uctv.private_ip}
            remotePort: 8892

    ssh_authorized_keys:
      - ${tls_private_key.lab_key.public_key_openssh}

    runcmd:
      - echo "Downloading UCT-V agent from Public Blob Storage..."
      - curl -L "https://connollystorageaccount.blob.core.windows.net/uctv-agents/gigamon-gigavue-uctv-6.12.00-amd64.deb" -o /tmp/uctv-agent.deb
      - echo "Installing UCT-V agent..."
      - dpkg -i /tmp/uctv-agent.deb || apt-get install -f -y
      - echo "UCT-V agent installed."
      - if [ -f /var/run/reboot-required ]; then reboot; fi
  EOF
}
