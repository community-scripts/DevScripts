#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://github.com/getfider/fider

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

var_mail_from="${var_mail_from:-noreply@example.com}"
var_smtp_port="${var_smtp_port:-587}"

msg_info "Installing Dependencies"
$STD apt install -y build-essential
msg_ok "Installed Dependencies"

setup_go
NODE_VERSION="24" setup_nodejs
PG_VERSION="17" setup_postgresql
PG_DB_NAME="fider" PG_DB_USER="fider" PG_DB_CREDS_FILE="/dev/null" setup_postgresql_db
fetch_and_deploy_gh_release "fider" "getfider/fider" "tarball"

msg_info "Building Fider"
cd /opt/fider
$STD npm ci
$STD make build-ssr
$STD make build-ui
VERSION="$(cat ~/.fider)" $STD make build-server
rm -rf node_modules etc ~/.npm
$STD go clean -cache -modcache
msg_ok "Built Fider"

msg_info "Configuring Fider"
mkdir -p /opt/fider_data
cat <<EOF >/opt/fider_data/.env
BASE_URL=http://${LOCAL_IP}:3000
DATABASE_URL=postgres://fider:${PG_DB_PASS}@localhost:5432/fider?sslmode=disable
JWT_SECRET=$(random_password 64)
EMAIL_NOREPLY=${var_mail_from}
EMAIL_SMTP_HOST=${var_smtp_host:-localhost}
EMAIL_SMTP_PORT=${var_smtp_port}
EMAIL_SMTP_USERNAME=${var_smtp_user:-}
EMAIL_SMTP_PASSWORD=${var_smtp_pass:-}
EMAIL_SMTP_ENABLE_STARTTLS=true
EMAIL_SMTP_ENABLE_IMPLICIT_TLS=$([[ "$var_smtp_port" == "465" ]] && echo true || echo false)
EOF
chmod 600 /opt/fider_data/.env
msg_ok "Configured Fider"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/fider.service
[Unit]
Description=Fider
After=network-online.target postgresql.service
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=/opt/fider
EnvironmentFile=/opt/fider_data/.env
ExecStartPre=/opt/fider/fider migrate
ExecStart=/opt/fider/fider
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now fider
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc
