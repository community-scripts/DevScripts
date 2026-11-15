#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Aditya Raj Singh (justadityaraj)
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://lightpanda.io/

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

fetch_and_deploy_gh_release "lightpanda" "lightpanda-io/browser" "binary"

msg_info "Creating Services"
cat <<EOF >/etc/systemd/system/lightpanda.service
[Unit]
Description=Lightpanda CDP Server
After=network.target

[Service]
Type=simple
User=root
Environment=LIGHTPANDA_DISABLE_TELEMETRY=true
ExecStart=/usr/bin/lightpanda serve --host 0.0.0.0 --advertise-host ${LOCAL_IP} --port 9222 --log-level info --block-private-networks
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
cat <<EOF >/etc/systemd/system/lightpanda-mcp.service
[Unit]
Description=Lightpanda MCP Server
After=network.target

[Service]
Type=simple
User=root
Environment=LIGHTPANDA_DISABLE_TELEMETRY=true
ExecStart=/usr/bin/lightpanda mcp --host 0.0.0.0 --port 9223 --block-private-networks
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now lightpanda lightpanda-mcp
msg_ok "Created Services"

motd_ssh
customize
cleanup_lxc
