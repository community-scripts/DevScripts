#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MrNRod
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/cedya77/aiometadata | Docs: https://github.com/cedya77/aiometadata/blob/dev/docs/ENVIRONMENT_VARIABLES.md

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt install -y redis-server
msg_ok "Installed Dependencies"

NODE_VERSION="24" setup_nodejs

fetch_and_deploy_gh_release "aiometadata" "cedya77/aiometadata" "tarball" "latest" "" "" "v"

msg_info "Configuring Redis"
REDIS_PASS=$(openssl rand -hex 24)
sed -i "s/^# requirepass foobared/requirepass ${REDIS_PASS}/" /etc/redis/redis.conf
systemctl enable -q --now redis-server
systemctl restart redis-server
msg_ok "Configured Redis"

msg_info "Building Application (Patience)"
cd /opt/aiometadata
$STD npm ci
$STD npm run build
$STD npm run build:backend
msg_ok "Built Application"

msg_info "Configuring Application"
mkdir -p /opt/aiometadata_data
cp /opt/aiometadata/.env.example /opt/aiometadata_data/.env
ADMIN_KEY=$(openssl rand -hex 24)
sed -i \
  -e "s|^HOST_NAME=.*|HOST_NAME=http://${LOCAL_IP}:3232|" \
  -e "s|^NODE_ENV=.*|NODE_ENV=production|" \
  -e "s|^DATABASE_URI=sqlite://addon/data/db.sqlite|DATABASE_URI=sqlite:///opt/aiometadata_data/db.sqlite|" \
  -e "s|^REDIS_URL=.*|REDIS_URL=redis://:${REDIS_PASS}@127.0.0.1:6379|" \
  -e "s|^# ADMIN_KEY=.*|ADMIN_KEY=${ADMIN_KEY}|" \
  /opt/aiometadata_data/.env
msg_ok "Configured Application"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/aiometadata.service
[Unit]
Description=AIOMetadata
After=network.target redis-server.service
Requires=redis-server.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/aiometadata
EnvironmentFile=/opt/aiometadata_data/.env
Environment="UV_THREADPOOL_SIZE=16"
Environment="DOTENV_CONFIG_QUIET=true"
ExecStart=/usr/bin/node dist/server/server.js
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now aiometadata
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc
