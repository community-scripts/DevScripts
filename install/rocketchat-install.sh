#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: william-aqn
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://www.rocket.chat/

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

if [[ -z "${var_admin_email:-}" ]]; then
  # unattended runs have no tty: read returns 1 on EOF
  read -r -p "${TAB3}Admin email address: " var_admin_email || true
fi
var_admin_email="${var_admin_email//[[:space:]]/}"
var_admin_email="${var_admin_email:-admin@example.com}"
if [[ ! "$var_admin_email" =~ ^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$ ]]; then
  msg_warn "Invalid email '${var_admin_email}', falling back to admin@example.com"
  var_admin_email="admin@example.com"
fi

msg_info "Installing Dependencies"
$STD apt install -y \
  build-essential \
  python3 \
  graphicsmagick \
  jq
msg_ok "Installed Dependencies"

MONGO_VERSION="8.0" setup_mongodb

# npm 12 cannot install this bundle
NODE_VERSION="22" NPM_VERSION="10" setup_nodejs

msg_info "Configuring MongoDB Replica Set"
if ! grep -q "^replication:" /etc/mongod.conf; then
  cat <<EOF >>/etc/mongod.conf
replication:
  replSetName: rs0
EOF
fi
systemctl restart mongod
for _ in {1..60}; do
  mongosh --quiet --eval "db.adminCommand('ping')" &>/dev/null && break
  sleep 1
done
if ! mongosh --quiet --eval "rs.status().ok" &>/dev/null; then
  $STD mongosh --quiet --eval 'rs.initiate({ _id: "rs0", members: [{ _id: 0, host: "127.0.0.1:27017" }] })'
fi
for _ in {1..60}; do
  [[ "$(mongosh --quiet --eval "db.hello().isWritablePrimary" 2>/dev/null)" == "true" ]] && break
  sleep 1
done
msg_ok "Configured MongoDB Replica Set"

RELEASE=$(curl -fsSL https://releases.rocket.chat/latest/info | jq -r '.tag')
fetch_and_deploy_from_url "https://releases.rocket.chat/${RELEASE}/download" "/opt/rocketchat"
echo "${RELEASE}" >~/.rocketchat

msg_info "Building Rocket.Chat ${RELEASE} (Patience)"
cd /opt/rocketchat/programs/server
$STD npm install
msg_ok "Built Rocket.Chat ${RELEASE}"

msg_info "Creating Configuration"
ADMIN_PASS=$(openssl rand -base64 24 | tr -dc 'a-zA-Z0-9' | cut -c1-24)
mkdir -p /etc/rocketchat
cat <<EOF >/etc/rocketchat/rocketchat.env
NODE_ENV=production
PORT=3000
ROOT_URL=http://${LOCAL_IP}:3000
MONGO_URL=mongodb://127.0.0.1:27017/rocketchat?replicaSet=rs0
ADMIN_USERNAME=admin
ADMIN_NAME=Administrator
ADMIN_EMAIL=${var_admin_email}
ADMIN_PASS=${ADMIN_PASS}
OVERWRITE_SETTING_Show_Setup_Wizard=completed
EOF
chmod 600 /etc/rocketchat/rocketchat.env
{
  echo "Rocket.Chat Admin"
  echo "Username: admin"
  echo "Password: ${ADMIN_PASS}"
  echo "Email: ${var_admin_email}"
} >~/rocketchat.creds
chmod 600 ~/rocketchat.creds
msg_ok "Created Configuration"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/rocketchat.service
[Unit]
Description=Rocket.Chat Server
After=network.target mongod.service
Requires=mongod.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/rocketchat
EnvironmentFile=/etc/rocketchat/rocketchat.env
ExecStart=/usr/bin/node /opt/rocketchat/main.js
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now rocketchat
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc
