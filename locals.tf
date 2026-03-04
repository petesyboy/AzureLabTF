# Local values for cloud-init scripts and Ubuntu image details
# These are separated from main.tf to keep it more readable

locals {
  # Gigamon version configuration
  # These locals derive the correct image SKU and version strings from the `gigamon_version` variable.
  gigamon_version_sku_code = replace(var.gigamon_version, ".", "") # e.g., "6.13" -> "613"

  fm_image_sku      = "gfm-azure-v${local.gigamon_version_sku_code}00"
  fm_image_version  = "${var.gigamon_version}.00" # NOTE: This was 6.12.1099. Using .00 as a default for the new version.

  uctv_image_sku    = "uctv-cntlr-v${local.gigamon_version_sku_code}00"
  uctv_image_version = "${var.gigamon_version}.00"

  vseries_image_sku = "vseries-node-v${local.gigamon_version_sku_code}00"
  vseries_image_version = "${var.gigamon_version}.00"

  # Ubuntu image configuration
  ubuntu_publisher = "Canonical"
  ubuntu_offer     = var.ubuntu_version == "24.04" ? "ubuntu-24_04-lts" : "ubuntu-22_04-lts"
  ubuntu_sku       = "server"
  ubuntu_version   = "latest"

  # Common script to fetch FM token from Key Vault using Managed Identity
  token_fetch_script = <<-EOF
    #!/usr/bin/env bash
    set -euo pipefail
    CONF="/etc/gigamon-cloud.conf"
    KV_NAME="${azurerm_key_vault.fm_token_kv.name}"
    SECRET_NAME="${var.fm_token_secret_name}"
    KV_API_VERSION="7.4"
    if [[ ! -f "$CONF" ]]; then exit 0; fi
    if ! grep -q "PLACEHOLDER_TOKEN" "$CONF"; then
      systemctl disable --now fm-token-fetch.timer >/dev/null 2>&1 || true
      exit 0
    fi
    MSI_JSON="$(curl -sS -H 'Metadata: true' 'http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https%3A%2F%2Fvault.azure.net' || true)"
    ACCESS_TOKEN=""
    if command -v jq >/dev/null 2>&1; then
      ACCESS_TOKEN="$(echo "$MSI_JSON" | jq -r '.access_token // empty' || true)"
    elif command -v python3 >/dev/null 2>&1; then
      ACCESS_TOKEN="$(python3 -c 'import json,sys; print(json.load(sys.stdin).get("access_token",""))' <<<"$MSI_JSON")"
    else
      ACCESS_TOKEN="$(echo "$MSI_JSON" | sed -n 's/.*"access_token"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
    fi
    if [[ -z "$ACCESS_TOKEN" ]]; then
      echo "No managed identity access token yet; will retry."
      exit 0
    fi
    SECRET_URL="https://$${KV_NAME}.vault.azure.net/secrets/$${SECRET_NAME}?api-version=$${KV_API_VERSION}"
    SECRET_JSON="$(curl -sS -H "Authorization: Bearer $${ACCESS_TOKEN}" "$SECRET_URL" || true)"
    FM_TOKEN=""
    if command -v jq >/dev/null 2>&1; then
      FM_TOKEN="$(echo "$SECRET_JSON" | jq -r '.value // empty' || true)"
    elif command -v python3 >/dev/null 2>&1; then
      FM_TOKEN="$(python3 -c 'import json,sys; print(json.load(sys.stdin).get("value",""))' <<<"$SECRET_JSON")"
    else
      FM_TOKEN="$(echo "$SECRET_JSON" | sed -n 's/.*"value"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
    fi
    if [[ -z "$FM_TOKEN" ]]; then
      echo "Secret not available yet; will retry."
      exit 0
    fi
    sed -i "s|^\\([[:space:]]*token:\\).*|\\1 $${FM_TOKEN}|" "$CONF"
    systemctl start gigamon-agent-refresh.service >/dev/null 2>&1 || true
    systemctl disable --now fm-token-fetch.timer >/dev/null 2>&1 || true
  EOF

  # Common script to restart services when config changes
  agent_refresh_script = <<-EOF
    #!/usr/bin/env bash
    set -euo pipefail
    CONF="/etc/gigamon-cloud.conf"
    # Determine service name based on what is installed
    if systemctl list-unit-files | grep -q "vseries-node.service"; then
      SERVICE="vseries-node"
    elif systemctl list-unit-files | grep -q "uctv.service"; then
      SERVICE="uctv"
    else
      exit 0
    fi
    if [[ ! -f "$CONF" ]]; then exit 0; fi
    if grep -q "PLACE_HOLDER_TOKEN" "$CONF"; then
      echo "Placeholder token still present; skipping restart."
      exit 0
    fi
    systemctl restart "$SERVICE"
  EOF

  # FM Cloud-Init: Minimal init.
  # Configuration is handled post-deployment via API.
  fm_cloud_init = <<-EOF
    #cloud-config
    packages: []
    runcmd:
      - echo "GigaVUE-FM ${var.gigamon_version} initializing..."
  EOF

  # UCT-V Controller Cloud-Init
  # Configuration is handled post-deployment via SSH direct push.
  uctv_cloud_init = <<-EOF
    #cloud-config
    packages: []
    runcmd:
      - echo "UCT-V Controller initialized. Waiting for configuration via SSH..."
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
            remoteAddress: fm.connolly.lab
            remotePort: 443

      - path: /usr/local/sbin/fetch-fm-token-from-keyvault.sh
        permissions: '0755'
        owner: root:root
        content: ${jsonencode(local.token_fetch_script)}

      - path: /etc/systemd/system/fm-token-fetch.service
        permissions: '0644'
        owner: root:root
        content: |
          [Unit]
          Description=Fetch FM token from Azure Key Vault
          After=network-online.target
          Wants=network-online.target

          [Service]
          Type=oneshot
          ExecStart=/usr/local/sbin/fetch-fm-token-from-keyvault.sh

      - path: /etc/systemd/system/fm-token-fetch.timer
        permissions: '0644'
        owner: root:root
        content: |
          [Unit]
          Description=Periodically fetch FM token from Azure Key Vault

          [Timer]
          OnBootSec=30s
          OnUnitActiveSec=60s
          RandomizedDelaySec=15s

          [Install]
          WantedBy=timers.target

      - path: /usr/local/sbin/gigamon-agent-refresh.sh
        permissions: '0755'
        owner: root:root
        content: |
          #!/usr/bin/env bash
          set -euo pipefail

          CONF="/etc/gigamon-cloud.conf"
          SERVICE="vseries-node"

          if [[ ! -f "$CONF" ]]; then
            exit 0
          fi

          if grep -q "PLACEHOLDER_TOKEN" "$CONF"; then
            echo "gigamon-cloud.conf still has placeholder token; skipping restart."
            exit 0
          fi

          systemctl restart "$SERVICE"

      - path: /etc/systemd/system/gigamon-agent-refresh.service
        permissions: '0644'
        owner: root:root
        content: |
          [Unit]
          Description=Refresh Gigamon agent after config change
          After=network-online.target
          Wants=network-online.target

          [Service]
          Type=oneshot
          ExecStart=/usr/local/sbin/gigamon-agent-refresh.sh

      - path: /etc/systemd/system/gigamon-agent-refresh.path
        permissions: '0644'
        owner: root:root
        content: |
          [Unit]
          Description=Watch /etc/gigamon-cloud.conf for changes

          [Path]
          PathChanged=/etc/gigamon-cloud.conf
          Unit=gigamon-agent-refresh.service

          [Install]
          WantedBy=multi-user.target

    runcmd:
      - echo "vSeries Node initialized. Waiting for configuration..."
      - systemctl daemon-reload
      - systemctl enable --now fm-token-fetch.timer || true
      - systemctl start fm-token-fetch.service || true
      - systemctl enable --now gigamon-agent-refresh.path || true
      - systemctl start gigamon-agent-refresh.service || true
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
      - ufw allow from uctv.connolly.lab || true
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
            remoteAddress: ${module.uctv_controller.private_ip}
            remotePort: 8892

      - path: /usr/local/sbin/fetch-fm-token-from-keyvault.sh
        permissions: '0755'
        owner: root:root
        content: |
          #!/usr/bin/env bash
          set -euo pipefail

          CONF="/etc/gigamon-cloud.conf"
          KV_NAME="${azurerm_key_vault.fm_token_kv.name}"
          SECRET_NAME="${var.fm_token_secret_name}"
          KV_API_VERSION="7.4"

          if [[ ! -f "$CONF" ]]; then
            exit 0
          fi

          if ! grep -q "PLACEHOLDER_TOKEN" "$CONF"; then
            systemctl disable --now fm-token-fetch.timer >/dev/null 2>&1 || true
            exit 0
          fi

          MSI_JSON="$(curl -sS -H 'Metadata: true' \
            'http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https%3A%2F%2Fvault.azure.net' || true)"
          ACCESS_TOKEN="$(echo "$MSI_JSON" | jq -r '.access_token // empty' || true)"
          if [[ -z "$ACCESS_TOKEN" ]]; then
            echo "No managed identity access token yet (RBAC propagation?); will retry."
            exit 0
          fi

          SECRET_URL="https://$${KV_NAME}.vault.azure.net/secrets/$${SECRET_NAME}?api-version=$${KV_API_VERSION}"
          SECRET_JSON="$(curl -sS -H "Authorization: Bearer $${ACCESS_TOKEN}" "$SECRET_URL" || true)"
          FM_TOKEN="$(echo "$SECRET_JSON" | jq -r '.value // empty' || true)"
          if [[ -z "$FM_TOKEN" ]]; then
            echo "Secret not available yet (or access denied); will retry."
            exit 0
          fi

          sed -i "s|^\\([[:space:]]*token:\\).*|\\1 $${FM_TOKEN}|" "$CONF"
          systemctl start gigamon-agent-refresh.service >/dev/null 2>&1 || true
          systemctl disable --now fm-token-fetch.timer >/dev/null 2>&1 || true

      - path: /etc/systemd/system/fm-token-fetch.service
        permissions: '0644'
        owner: root:root
        content: |
          [Unit]
          Description=Fetch FM token from Azure Key Vault
          After=network-online.target
          Wants=network-online.target

          [Service]
          Type=oneshot
          ExecStart=/usr/local/sbin/fetch-fm-token-from-keyvault.sh

      - path: /etc/systemd/system/fm-token-fetch.timer
        permissions: '0644'
        owner: root:root
        content: |
          [Unit]
          Description=Periodically fetch FM token from Azure Key Vault

          [Timer]
          OnBootSec=30s
          OnUnitActiveSec=60s
          RandomizedDelaySec=15s

          [Install]
          WantedBy=timers.target

      - path: /usr/local/sbin/gigamon-agent-refresh.sh
        permissions: '0755'
        owner: root:root
        content: |
          #!/usr/bin/env bash
          set -euo pipefail

          CONF="/etc/gigamon-cloud.conf"
          SERVICE="uctv"

          if [[ ! -f "$CONF" ]]; then
            exit 0
          fi

          if grep -q "PLACEHOLDER_TOKEN" "$CONF"; then
            echo "gigamon-cloud.conf still has placeholder token; skipping restart."
            exit 0
          fi

          systemctl restart "$SERVICE"

      - path: /etc/systemd/system/gigamon-agent-refresh.service
        permissions: '0644'
        owner: root:root
        content: |
          [Unit]
          Description=Refresh Gigamon agent after config change
          After=network-online.target
          Wants=network-online.target

          [Service]
          Type=oneshot
          ExecStart=/usr/local/sbin/gigamon-agent-refresh.sh

      - path: /etc/systemd/system/gigamon-agent-refresh.path
        permissions: '0644'
        owner: root:root
        content: |
          [Unit]
          Description=Watch /etc/gigamon-cloud.conf for changes

          [Path]
          PathChanged=/etc/gigamon-cloud.conf
          Unit=gigamon-agent-refresh.service

          [Install]
          WantedBy=multi-user.target

    ssh_authorized_keys:
      - ${tls_private_key.lab_key.public_key_openssh}

    runcmd:
      - echo "Downloading UCT-V agent from Public Blob Storage..."
      - curl -L --retry 10 --retry-delay 10 --retry-connrefused "${azurerm_storage_account.lab_sa.primary_blob_endpoint}${azurerm_storage_container.uctv_container.name}/gigamon-gigavue-uctv-${local.uctv_image_version}-amd64.deb" -o /tmp/uctv-agent.deb
      - echo "Installing UCT-V agent..."
      - dpkg -i /tmp/uctv-agent.deb || apt-get install -f -y
      - echo "UCT-V agent installed."
      - systemctl daemon-reload
      - systemctl enable --now fm-token-fetch.timer || true
      - systemctl start fm-token-fetch.service || true
      - systemctl enable --now gigamon-agent-refresh.path || true
      - systemctl start gigamon-agent-refresh.service || true
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
            remoteAddress: ${module.uctv_controller.private_ip}
            remotePort: 8892

      - path: /usr/local/sbin/fetch-fm-token-from-keyvault.sh
        permissions: '0755'
        owner: root:root
        content: |
          #!/usr/bin/env bash
          set -euo pipefail

          CONF="/etc/gigamon-cloud.conf"
          KV_NAME="${azurerm_key_vault.fm_token_kv.name}"
          SECRET_NAME="${var.fm_token_secret_name}"
          KV_API_VERSION="7.4"

          if [[ ! -f "$CONF" ]]; then
            exit 0
          fi

          if ! grep -q "PLACEHOLDER_TOKEN" "$CONF"; then
            systemctl disable --now fm-token-fetch.timer >/dev/null 2>&1 || true
            exit 0
          fi

          MSI_JSON="$(curl -sS -H 'Metadata: true' \
            'http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https%3A%2F%2Fvault.azure.net' || true)"
          ACCESS_TOKEN="$(echo "$MSI_JSON" | jq -r '.access_token // empty' || true)"
          if [[ -z "$ACCESS_TOKEN" ]]; then
            echo "No managed identity access token yet (RBAC propagation?); will retry."
            exit 0
          fi

          SECRET_URL="https://$${KV_NAME}.vault.azure.net/secrets/$${SECRET_NAME}?api-version=$${KV_API_VERSION}"
          SECRET_JSON="$(curl -sS -H "Authorization: Bearer $${ACCESS_TOKEN}" "$SECRET_URL" || true)"
          FM_TOKEN="$(echo "$SECRET_JSON" | jq -r '.value // empty' || true)"
          if [[ -z "$FM_TOKEN" ]]; then
            echo "Secret not available yet (or access denied); will retry."
            exit 0
          fi

          sed -i "s|^\\([[:space:]]*token:\\).*|\\1 $${FM_TOKEN}|" "$CONF"
          systemctl start gigamon-agent-refresh.service >/dev/null 2>&1 || true
          systemctl disable --now fm-token-fetch.timer >/dev/null 2>&1 || true

      - path: /etc/systemd/system/fm-token-fetch.service
        permissions: '0644'
        owner: root:root
        content: |
          [Unit]
          Description=Fetch FM token from Azure Key Vault
          After=network-online.target
          Wants=network-online.target

          [Service]
          Type=oneshot
          ExecStart=/usr/local/sbin/fetch-fm-token-from-keyvault.sh

      - path: /etc/systemd/system/fm-token-fetch.timer
        permissions: '0644'
        owner: root:root
        content: |
          [Unit]
          Description=Periodically fetch FM token from Azure Key Vault

          [Timer]
          OnBootSec=30s
          OnUnitActiveSec=60s
          RandomizedDelaySec=15s

          [Install]
          WantedBy=timers.target

      - path: /usr/local/sbin/gigamon-agent-refresh.sh
        permissions: '0755'
        owner: root:root
        content: |
          #!/usr/bin/env bash
          set -euo pipefail

          CONF="/etc/gigamon-cloud.conf"
          SERVICE="uctv"

          if [[ ! -f "$CONF" ]]; then
            exit 0
          fi

          if grep -q "PLACEHOLDER_TOKEN" "$CONF"; then
            echo "gigamon-cloud.conf still has placeholder token; skipping restart."
            exit 0
          fi

          systemctl restart "$SERVICE"

      - path: /etc/systemd/system/gigamon-agent-refresh.service
        permissions: '0644'
        owner: root:root
        content: |
          [Unit]
          Description=Refresh Gigamon agent after config change
          After=network-online.target
          Wants=network-online.target

          [Service]
          Type=oneshot
          ExecStart=/usr/local/sbin/gigamon-agent-refresh.sh

      - path: /etc/systemd/system/gigamon-agent-refresh.path
        permissions: '0644'
        owner: root:root
        content: |
          [Unit]
          Description=Watch /etc/gigamon-cloud.conf for changes

          [Path]
          PathChanged=/etc/gigamon-cloud.conf
          Unit=gigamon-agent-refresh.service

          [Install]
          WantedBy=multi-user.target

    ssh_authorized_keys:
      - ${tls_private_key.lab_key.public_key_openssh}

    runcmd:
      - echo "Downloading UCT-V agent from Public Blob Storage..."
      - curl -L --retry 10 --retry-delay 10 --retry-connrefused "${azurerm_storage_account.lab_sa.primary_blob_endpoint}${azurerm_storage_container.uctv_container.name}/gigamon-gigavue-uctv-${local.uctv_image_version}-amd64.deb" -o /tmp/uctv-agent.deb
      - echo "Installing UCT-V agent..."
      - dpkg -i /tmp/uctv-agent.deb || apt-get install -f -y
      - echo "UCT-V agent installed."
      - systemctl daemon-reload
      - systemctl enable --now fm-token-fetch.timer || true
      - systemctl start fm-token-fetch.service || true
      - systemctl enable --now gigamon-agent-refresh.path || true
      - systemctl start gigamon-agent-refresh.service || true
      - if [ -f /var/run/reboot-required ]; then reboot; fi
  EOF
}
