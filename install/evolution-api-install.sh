#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://github.com/evolution-foundation/evolution-api

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

var_api_key="${var_api_key:-$(random_password 32)}"
var_server_url="${var_server_url:-http://${LOCAL_IP}:8080}"

PG_VERSION="17" setup_postgresql
PG_DB_NAME="evolution" PG_DB_USER="evolution" PG_DB_CREDS_FILE="/dev/null" setup_postgresql_db
NODE_VERSION="24" setup_nodejs
fetch_and_deploy_gh_release "evolution-api" "evolution-foundation/evolution-api" "tarball"

msg_info "Configuring Evolution API"
mkdir -p /opt/evolution-api_data/instances /opt/evolution-api_data/store
cat <<EOF >/opt/evolution-api_data/.env
SERVER_NAME=evolution
SERVER_TYPE=http
SERVER_PORT=8080
SERVER_URL=${var_server_url}
CORS_ORIGIN=*
CORS_METHODS=GET,POST,PUT,DELETE
CORS_CREDENTIALS=true
AUTHENTICATION_API_KEY=${var_api_key}
AUTHENTICATION_EXPOSE_IN_FETCH_INSTANCES=false
DATABASE_PROVIDER=postgresql
DATABASE_CONNECTION_URI=postgresql://evolution:${PG_DB_PASS}@localhost:5432/evolution?schema=public
DATABASE_CONNECTION_CLIENT_NAME=evolution
DATABASE_SAVE_DATA_INSTANCE=true
DATABASE_SAVE_DATA_NEW_MESSAGE=true
DATABASE_SAVE_MESSAGE_UPDATE=true
DATABASE_SAVE_DATA_CONTACTS=true
DATABASE_SAVE_DATA_CHATS=true
DATABASE_SAVE_DATA_HISTORIC=true
DATABASE_SAVE_DATA_LABELS=true
DATABASE_SAVE_IS_ON_WHATSAPP=true
CACHE_REDIS_ENABLED=false
CACHE_LOCAL_ENABLED=true
DEL_INSTANCE=false
LANGUAGE=en
LOG_LEVEL=ERROR,WARN,INFO,LOG
LOG_COLOR=false
LOG_BAILEYS=error
TYPEBOT_ENABLED=true
CHATWOOT_ENABLED=true
OPENAI_ENABLED=true
DIFY_ENABLED=true
N8N_ENABLED=true
EVOAI_ENABLED=true
FLOWISE_ENABLED=true
TELEMETRY_ENABLED=false
EOF
chmod 600 /opt/evolution-api_data/.env
ln -sf /opt/evolution-api_data/.env /opt/evolution-api/.env
ln -sfn /opt/evolution-api_data/instances /opt/evolution-api/instances
ln -sfn /opt/evolution-api_data/store /opt/evolution-api/store
msg_ok "Configured Evolution API"

msg_info "Building Evolution API"
cd /opt/evolution-api
$STD npm ci
$STD npm run db:generate
$STD npm run build
$STD npm run db:deploy
$STD npm prune --omit=dev
rm -rf ~/.npm
msg_ok "Built Evolution API"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/evolution-api.service
[Unit]
Description=Evolution API
After=network-online.target postgresql.service
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=/opt/evolution-api
ExecStart=/usr/bin/npm run start:prod
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now evolution-api
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc
