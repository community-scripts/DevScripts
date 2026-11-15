#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://github.com/redis/RedisInsight

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
  git \
  python3
msg_ok "Installed Dependencies"

fetch_and_deploy_gh_release "redisinsight" "redis/RedisInsight" "tarball"
NODE_VERSION="$(cut -d. -f1 /opt/redisinsight/.nvmrc)" NODE_MODULE="yarn" setup_nodejs

msg_info "Building Redis Insight"
cd /opt/redisinsight
SKIP_POSTINSTALL=1 ELECTRON_SKIP_BINARY_DOWNLOAD=1 $STD yarn install
$STD yarn --cwd redisinsight/api install
$STD yarn build:ui
$STD yarn build:statics
$STD yarn build:api
SKIP_API_CLIENT_GEN=1 $STD yarn --cwd redisinsight/api install --production
cp redisinsight/api/.yarnclean.prod redisinsight/api/.yarnclean
$STD yarn --cwd redisinsight/api autoclean --force
rm -rf node_modules redisinsight/ui/src/packages/*/node_modules
$STD yarn cache clean
msg_ok "Built Redis Insight"

msg_info "Configuring Redis Insight"
mkdir -p /opt/redisinsight_data
cat <<EOF >/opt/redisinsight_data/.env
NODE_ENV=production
RI_APP_PORT=5540
RI_APP_FOLDER_ABSOLUTE_PATH=/opt/redisinsight_data
RI_ENCRYPTION_KEY=$(random_password 32)
EOF
chmod 600 /opt/redisinsight_data/.env
msg_ok "Configured Redis Insight"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/redisinsight.service
[Unit]
Description=Redis Insight
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/redisinsight
EnvironmentFile=/opt/redisinsight_data/.env
ExecStart=/usr/bin/node redisinsight/api/dist/src/main
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now redisinsight
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc
