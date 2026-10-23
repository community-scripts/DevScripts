#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: andy-vdg
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://agentgateway.dev/

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

fetch_and_deploy_gh_release "agentgateway" "agentgateway/agentgateway" "singlefile" "latest" "/opt/agentgateway" "agentgateway-linux-$(arch_resolve "amd64" "arm64")"

msg_info "Verifying agentgateway Checksum"
AGW_SUM=$(curl -fsSL "https://github.com/agentgateway/agentgateway/releases/download/v$(cat ~/.agentgateway)/agentgateway-linux-$(arch_resolve "amd64" "arm64").sha256" | awk '{print $1}')
if [[ -z "$AGW_SUM" || "$AGW_SUM" != "$(sha256sum /opt/agentgateway/agentgateway | awk '{print $1}')" ]]; then
  msg_error "agentgateway checksum does not match the release"
  exit 1
fi
chmod +x /opt/agentgateway/agentgateway
msg_ok "Verified agentgateway Checksum"

msg_info "Configuring agentgateway"
mkdir -p /etc/agentgateway /opt/agentgateway_data
cat <<EOF >/etc/agentgateway/config.yaml
# yaml-language-server: \$schema=https://agentgateway.dev/schema/config
# The config agentgateway bootstraps on first run: traffic and the UI on port 4000,
# state in SQLite. The UI has no login until you add policies:
# https://agentgateway.dev/docs/standalone/latest/documentation/setup/ui/secure-ui/
config:
  database:
    url: sqlite:///opt/agentgateway_data/data.db
gateways:
  default:
    port: 4000
ui:
  gateways: default
EOF
chmod 600 /etc/agentgateway/config.yaml
msg_ok "Configured agentgateway"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/agentgateway.service
[Unit]
Description=agentgateway
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
ExecStart=/opt/agentgateway/agentgateway -f /etc/agentgateway/config.yaml
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now agentgateway
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc
