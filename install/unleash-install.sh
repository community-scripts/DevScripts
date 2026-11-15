#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://github.com/Unleash/unleash

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

NODE_VERSION="22" setup_nodejs
PG_VERSION="17" setup_postgresql
PG_DB_NAME="unleash" PG_DB_USER="unleash" PG_DB_CREDS_FILE="/dev/null" setup_postgresql_db

msg_info "Installing Unleash"
UNLEASH_VERSION="${var_appversion:-latest}"
mkdir -p /opt/unleash
cd /opt/unleash
$STD npm init -y
$STD npm install --ignore-scripts "unleash-server@${UNLEASH_VERSION#v}"
cat <<EOF >~/.unleash
$(node -p "require('/opt/unleash/node_modules/unleash-server/package.json').version")
EOF
msg_ok "Installed Unleash"

msg_info "Configuring Unleash"
mkdir -p /opt/unleash_data
cat <<EOF >/opt/unleash_data/.env
DATABASE_URL=postgres://unleash:${PG_DB_PASS}@localhost:5432/unleash
DATABASE_SSL=false
UNLEASH_URL=http://${LOCAL_IP}:4242
UNLEASH_SECRET=$(random_password 64)
UNLEASH_DEFAULT_ADMIN_USERNAME=${var_admin_user:-admin}
UNLEASH_DEFAULT_ADMIN_PASSWORD=${var_admin_pass:-$(random_password)}
EOF
chmod 600 /opt/unleash_data/.env
msg_ok "Configured Unleash"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/unleash.service
[Unit]
Description=Unleash
After=network.target postgresql.service
Wants=postgresql.service

[Service]
Type=simple
WorkingDirectory=/opt/unleash
Environment=NODE_ENV=production
Environment=TZ=UTC
EnvironmentFile=/opt/unleash_data/.env
ExecStart=/usr/bin/node /opt/unleash/node_modules/unleash-server/dist/server.js
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now unleash
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc
