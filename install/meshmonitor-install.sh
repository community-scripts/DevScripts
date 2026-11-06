#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: clartek
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://meshmonitor.org/

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing MeshMonitor Dependencies"
$STD apt install -y \
  build-essential \
  git \
  python3-dev \
  libsqlite3-dev \
  unzip
msg_ok "Installed MeshMonitor Dependencies"

NODE_VERSION="24" setup_nodejs
setup_uv

fetch_and_deploy_gh_release "meshmonitor" "Yeraze/meshmonitor" "tarball"

# GitHub source archives omit submodules; use the commits pinned by this release.
github_api_call "https://api.github.com/repos/Yeraze/meshmonitor/git/trees/v$(cat ~/.meshmonitor)" /tmp/meshmonitor-tree.json
protobuf_commit=$(jq -er '.tree[] | select(.path == "protobufs" and .type == "commit") | .sha' /tmp/meshmonitor-tree.json)
takpacket_commit=$(jq -er '.tree[] | select(.path == "takpacket-sdk" and .type == "commit") | .sha' /tmp/meshmonitor-tree.json)
fetch_and_deploy_from_url "https://github.com/meshtastic/protobufs/archive/${protobuf_commit}.tar.gz" /opt/meshmonitor/protobufs
fetch_and_deploy_from_url "https://github.com/meshtastic/TAKPacket-SDK/archive/${takpacket_commit}.tar.gz" /opt/meshmonitor/takpacket-sdk
rm -f /tmp/meshmonitor-tree.json

msg_info "Building MeshMonitor"
cd /opt/meshmonitor || exit 1
# The lockfile uses SSH for a public dependency; installation must not require SSH keys.
$STD git config --global url."https://github.com/".insteadOf "ssh://git@github.com/"
PUPPETEER_SKIP_DOWNLOAD=true $STD npm install --legacy-peer-deps
$STD npm run build
$STD npm run build:server
$STD npm prune --omit=dev --legacy-peer-deps
msg_ok "Built MeshMonitor"

msg_info "Installing MeshMonitor Python Dependencies"
$STD uv venv --seed /opt/meshmonitor-venv
$STD uv pip install --python /opt/meshmonitor-venv/bin/python apprise requests "paho-mqtt<2.0" meshtastic meshcore-cli
msg_ok "Installed MeshMonitor Python Dependencies"

msg_info "Configuring MeshMonitor"
mkdir -p /etc/meshmonitor /data/{apprise-config,scripts,logs}
cat <<EOF >/etc/meshmonitor/meshmonitor.env
NODE_ENV=production
PORT=3001
DATABASE_PATH=/data/meshmonitor.db
SESSION_SECRET=$(random_password 64)
COOKIE_SECURE=false
ALLOWED_ORIGINS=http://${LOCAL_IP}:3001
APPRISE_URL=http://127.0.0.1:8000
APPRISE_HOST=127.0.0.1
APPRISE_CONFIG_DIR=/data/apprise-config
APPRISE_STATEFUL_MODE=simple
EOF
chmod 600 /etc/meshmonitor/meshmonitor.env
msg_ok "Configured MeshMonitor"

msg_info "Creating MeshMonitor Services"
cat <<EOF >/etc/systemd/system/meshmonitor-apprise.service
[Unit]
Description=MeshMonitor Apprise Notification Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/meshmonitor
EnvironmentFile=/etc/meshmonitor/meshmonitor.env
ExecStart=/opt/meshmonitor-venv/bin/python /opt/meshmonitor/docker/apprise-api.py
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
cat <<EOF >/etc/systemd/system/meshmonitor.service
[Unit]
Description=MeshMonitor
After=network.target meshmonitor-apprise.service
Wants=meshmonitor-apprise.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/meshmonitor
EnvironmentFile=/etc/meshmonitor/meshmonitor.env
Environment=PATH=/opt/meshmonitor-venv/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
ExecStart=/usr/bin/node /opt/meshmonitor/dist/server/server.js
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now meshmonitor-apprise meshmonitor
msg_ok "Created MeshMonitor Services"

motd_ssh
customize
cleanup_lxc
