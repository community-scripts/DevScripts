#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://github.com/eduardolat/pgbackweb

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

PG_VERSION="18" setup_postgresql
PG_DB_NAME="pgbackweb" PG_DB_USER="pgbackweb" PG_DB_CREDS_FILE="/dev/null" setup_postgresql_db

msg_info "Installing Dependencies"
$STD apt install -y \
  unzip \
  postgresql-client-13 \
  postgresql-client-14 \
  postgresql-client-15 \
  postgresql-client-16 \
  postgresql-client-17
msg_ok "Installed Dependencies"

setup_go
NODE_VERSION="22" setup_nodejs
fetch_and_deploy_gh_release "task" "go-task/task" "binary"
fetch_and_deploy_gh_release "sqlc" "sqlc-dev/sqlc" "prebuild" "latest" "/usr/local/bin" "sqlc_*_linux_$(arch_resolve).tar.gz"
fetch_and_deploy_gh_release "goose" "pressly/goose" "singlefile" "latest" "/usr/local/bin" "goose_linux_$(arch_resolve "x86_64" "arm64")"
fetch_and_deploy_gh_release "pgbackweb" "eduardolat/pgbackweb" "tarball"

msg_info "Building PG Back Web"
cd /opt/pgbackweb
$STD bash ./scripts/set-version.sh "v$(cat ~/.pgbackweb)"
$STD npm ci
$STD task build
rm -rf node_modules
msg_ok "Built PG Back Web"

msg_info "Configuring PG Back Web"
mkdir -p /opt/pgbackweb_data/backups
# Local destinations are hardcoded to /backups
ln -sfn /opt/pgbackweb_data/backups /backups
cat <<EOF >/opt/pgbackweb_data/.env
PBW_ENCRYPTION_KEY=$(random_password 32)
PBW_POSTGRES_CONN_STRING=postgresql://pgbackweb:${PG_DB_PASS}@localhost:5432/pgbackweb?sslmode=disable
PBW_LISTEN_HOST=0.0.0.0
PBW_LISTEN_PORT=8085
EOF
chmod 600 /opt/pgbackweb_data/.env
msg_ok "Configured PG Back Web"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/pgbackweb.service
[Unit]
Description=PG Back Web
After=network.target postgresql.service
Wants=postgresql.service

[Service]
Type=simple
WorkingDirectory=/opt/pgbackweb_data
EnvironmentFile=/opt/pgbackweb_data/.env
ExecStartPre=/usr/local/bin/goose -dir /opt/pgbackweb/internal/database/migrations postgres \${PBW_POSTGRES_CONN_STRING} up
ExecStart=/opt/pgbackweb/dist/app
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now pgbackweb
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc
