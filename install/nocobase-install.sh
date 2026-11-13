#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://github.com/nocobase/nocobase

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

NODE_VERSION="22" NODE_MODULE="yarn" setup_nodejs
PG_VERSION="17" setup_postgresql
PG_DB_NAME="nocobase" PG_DB_USER="nocobase" PG_DB_CREDS_FILE="/dev/null" setup_postgresql_db

msg_info "Installing NocoBase"
NOCOBASE_VERSION="${var_appversion:-latest}"
cd /opt
$STD npx -y "create-nocobase-app@${NOCOBASE_VERSION#v}" nocobase --skip-dev-dependencies -d postgres
mkdir -p /opt/nocobase_data/storage
cat <<EOF >/opt/nocobase_data/.env
APP_ENV=production
APP_KEY=$(random_password 64)
APP_PORT=13000
API_BASE_PATH=/api/
STORAGE_PATH=/opt/nocobase_data/storage
DB_LOGGING=off
DB_DIALECT=postgres
DB_HOST=localhost
DB_PORT=5432
DB_DATABASE=nocobase
DB_USER=nocobase
DB_PASSWORD=${PG_DB_PASS}
INIT_ROOT_EMAIL=${var_admin_email:-admin@nocobase.com}
INIT_ROOT_PASSWORD=${var_admin_pass:-$(random_password)}
INIT_ROOT_NICKNAME=Super Admin
INIT_ROOT_USERNAME=nocobase
EOF
chmod 600 /opt/nocobase_data/.env
rm -rf /opt/nocobase/storage
ln -sf /opt/nocobase_data/.env /opt/nocobase/.env
cd /opt/nocobase
$STD yarn install --production
$STD yarn nocobase install --lang=en-US
$STD yarn cache clean
msg_ok "Installed NocoBase"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/nocobase.service
[Unit]
Description=NocoBase
After=network.target postgresql.service
Wants=postgresql.service

[Service]
Type=simple
WorkingDirectory=/opt/nocobase
ExecStart=/usr/bin/yarn start
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now nocobase
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc
