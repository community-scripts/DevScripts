#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://github.com/cupcakearmy/cryptgeon

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
  pkg-config \
  libssl-dev \
  valkey-server \
  nginx
msg_ok "Installed Dependencies"

msg_info "Configuring Valkey"
# Notes stay in RAM only, as in upstream's compose file
cat <<EOF >>/etc/valkey/valkey.conf
save ""
maxmemory 256mb
maxmemory-policy allkeys-lru
EOF
systemctl restart valkey-server
rm -f /var/lib/valkey/dump.rdb
msg_ok "Configured Valkey"

fetch_and_deploy_gh_release "cryptgeon" "cupcakearmy/cryptgeon" "tarball"
RUST_PROFILE="minimal" setup_rust
NODE_VERSION="24" NODE_MODULE="pnpm@$(jq -r '.packageManager | split("@")[1]' /opt/cryptgeon/package.json)" setup_nodejs

msg_info "Building Cryptgeon"
cd /opt/cryptgeon
$STD pnpm install --frozen-lockfile
$STD pnpm run build
cd /opt/cryptgeon/packages/backend
$STD cargo build --release --locked
cp target/release/cryptgeon /opt/cryptgeon/cryptgeon
rm -rf /opt/cryptgeon/packages/backend/target /opt/cryptgeon/node_modules /opt/cryptgeon/packages/*/node_modules
msg_ok "Built Cryptgeon"

msg_info "Configuring Cryptgeon"
mkdir -p /opt/cryptgeon_data
cat <<EOF >/opt/cryptgeon_data/.env
LISTEN_ADDR=127.0.0.1:8000
REDIS=redis://127.0.0.1/
SIZE_LIMIT=4 MiB
MAX_VIEWS=100
MAX_EXPIRATION=360
ALLOW_ADVANCED=true
ALLOW_FILES=true
THEME_NEW_NOTE_NOTICE=true
EOF
create_self_signed_cert "cryptgeon"
cat <<'EOF' >/etc/nginx/sites-available/cryptgeon
server {
    listen 80 default_server;
    server_name _;
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl default_server;
    http2 on;
    server_name _;

    ssl_certificate /etc/ssl/cryptgeon/cryptgeon.crt;
    ssl_certificate_key /etc/ssl/cryptgeon/cryptgeon.key;

    client_max_body_size 0;
    proxy_request_buffering off;

    location / {
        proxy_pass http://127.0.0.1:8000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
EOF
nginx_enable_site "cryptgeon"
msg_ok "Configured Cryptgeon"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/cryptgeon.service
[Unit]
Description=Cryptgeon
After=network.target valkey-server.service
Requires=valkey-server.service

[Service]
Type=simple
WorkingDirectory=/opt/cryptgeon
EnvironmentFile=/opt/cryptgeon_data/.env
Environment=FRONTEND_PATH=/opt/cryptgeon/packages/frontend/build
ExecStart=/opt/cryptgeon/cryptgeon
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now cryptgeon
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc
