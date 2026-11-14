#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://github.com/rmyndharis/OpenWA

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt install -y \
  build-essential \
  python3 \
  chromium \
  fonts-liberation
msg_ok "Installed Dependencies"

setup_ffmpeg
NODE_VERSION="22" setup_nodejs
fetch_and_deploy_gh_release "openwa" "rmyndharis/OpenWA" "tarball"

msg_info "Building OpenWA"
cd /opt/openwa
export PUPPETEER_SKIP_DOWNLOAD=true
$STD npm ci
$STD npm run build
$STD npm run dashboard:build
$STD npm prune --omit=dev
rm -rf dashboard/node_modules ~/.npm
msg_ok "Built OpenWA"

msg_info "Configuring OpenWA"
mkdir -p /opt/openwa_data/data
cat <<EOF >/opt/openwa_data/.env
NODE_ENV=production
PORT=2785
API_MASTER_KEY=${var_api_key:-$(random_password 40)}
CSP_UPGRADE_INSECURE_REQUESTS=false
PUPPETEER_EXECUTABLE_PATH=/usr/bin/chromium
EOF
chmod 600 /opt/openwa_data/.env
msg_ok "Configured OpenWA"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/openwa.service
[Unit]
Description=OpenWA WhatsApp API Gateway
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=/opt/openwa_data
ExecStart=/usr/bin/node /opt/openwa/dist/main
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now openwa
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc
