#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Lazztech
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://github.com/Lazztech/Libre-Closet

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

NODE_VERSION="22" setup_nodejs

fetch_and_deploy_gh_tag "libre-closet" "Lazztech/Libre-Closet"

msg_info "Building Libre Closet"
cd /opt/libre-closet
$STD npm ci
$STD npm run build
msg_ok "Built Libre Closet"

msg_info "Configuring Libre Closet"
mkdir -p /opt/libre-closet_data
cat <<EOF >/opt/libre-closet_data/.env
NODE_ENV=production
APP_NAME=Libre Closet
DATA_PATH=/opt/libre-closet_data
AUTH_ENABLED=false
PWA_ENABLED=true
ACCESS_TOKEN_SECRET=$(openssl rand -base64 60)
EOF
chmod 600 /opt/libre-closet_data/.env
msg_ok "Configured Libre Closet"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/libre-closet.service
[Unit]
Description=Libre Closet
After=network.target

[Service]
Type=simple
WorkingDirectory=/opt/libre-closet
EnvironmentFile=/opt/libre-closet_data/.env
ExecStart=/usr/bin/node dist/main
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now libre-closet
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc
