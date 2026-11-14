#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://github.com/tiagozip/cap

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

var_admin_key="${var_admin_key:-$(random_password 48)}"
if ((${#var_admin_key} < 12)); then
  msg_error "The admin key needs at least 12 characters"
  exit 64
fi

msg_info "Installing Valkey"
$STD apt install -y valkey-server
sed -i 's/^appendonly no/appendonly yes/' /etc/valkey/valkey.conf
systemctl restart valkey-server
msg_ok "Installed Valkey"

NODE_VERSION="24" NODE_MODULE="bun" setup_nodejs
fetch_and_deploy_gh_release "cap-captcha" "tiagozip/cap" "tarball" "latest" "/opt/cap-captcha" "" "capd@"

msg_info "Building Cap"
cd /opt/cap-captcha/capd
$STD bun install --frozen-lockfile
$STD bun run build
rm -rf node_modules
$STD bun install --frozen-lockfile --production
rm -rf node_modules/capjs-core
mkdir -p node_modules/capjs-core
cp -r ../core/package.json ../core/src node_modules/capjs-core/
rm -rf ~/.bun/install/cache
msg_ok "Built Cap"

msg_info "Configuring Cap"
mkdir -p /opt/cap-captcha_data
cat <<EOF >/opt/cap-captcha_data/.env
NODE_ENV=production
SERVER_PORT=3000
DATA_DIR=/opt/cap-captcha_data
VALKEY_URL=redis://127.0.0.1:6379
ADMIN_KEY='${var_admin_key}'
EOF
chmod 600 /opt/cap-captcha_data/.env
msg_ok "Configured Cap"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/cap-captcha.service
[Unit]
Description=Cap CAPTCHA Server
After=network.target valkey-server.service
Requires=valkey-server.service

[Service]
Type=simple
WorkingDirectory=/opt/cap-captcha/capd
EnvironmentFile=/opt/cap-captcha_data/.env
ExecStart=/usr/bin/bun run src/index.js
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now cap-captcha
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc
