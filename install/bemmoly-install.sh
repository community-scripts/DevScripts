#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Shrijayan
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://github.com/bemmoly/bemmoly

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

# Changesets use uuidv7() (Postgres 18), vector columns and trigram indexes
PG_VERSION="18" PG_MODULES="pgvector" setup_postgresql
PG_DB_NAME="bemmoly" PG_DB_USER="bemmoly" PG_DB_EXTENSIONS="vector,pg_trgm" setup_postgresql_db

fetch_and_deploy_gh_release "bemmoly" "bemmoly/bemmoly" "tarball"
NODE_VERSION="24" NODE_MODULE="$(jq -r '.packageManager' /opt/bemmoly/package.json)" setup_nodejs

msg_info "Building Bemmoly"
cd /opt/bemmoly
$STD pnpm install --frozen-lockfile
$STD pnpm --filter @bemmoly/web build
msg_ok "Built Bemmoly"

msg_info "Configuring Bemmoly"
mkdir -p /opt/bemmoly_data/{data,backups}
cat <<EOT >/opt/bemmoly_data/.env
NODE_ENV=production
PORT=8080
DATABASE_URL=postgresql://bemmoly:${PG_DB_PASS}@localhost:5432/bemmoly
BEMMOLY_PUBLIC_URL=http://${LOCAL_IP}:8080
BEMMOLY_SECRET_KEY=$(openssl rand -base64 32)
BEMMOLY_BACKUP_PASSPHRASE=$(openssl rand -base64 32)
BEMMOLY_DATA_DIR=/opt/bemmoly_data/data
BEMMOLY_BACKUP_DIR=/opt/bemmoly_data/backups
BEMMOLY_PG_BIN_DIR=/usr/lib/postgresql/18/bin
LOG_LEVEL=info
EOT
chmod 600 /opt/bemmoly_data/.env
cd /opt/bemmoly/apps/server
$STD node --env-file=/opt/bemmoly_data/.env src/cli.ts db update
msg_ok "Configured Bemmoly"

msg_info "Creating Service"
cat <<EOT >/etc/systemd/system/bemmoly.service
[Unit]
Description=Bemmoly
After=network.target postgresql.service
Requires=postgresql.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/bemmoly/apps/server
EnvironmentFile=/opt/bemmoly_data/.env
ExecStart=/usr/bin/node --import @bemmoly/core/telemetry/preload src/server.ts
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOT
systemctl enable -q --now bemmoly
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc
