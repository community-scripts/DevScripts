#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://github.com/heyform/heyform

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
  python3 \
  nginx \
  redis-server
msg_ok "Installed Dependencies"

setup_mongodb
fetch_and_deploy_gh_release "heyform" "heyform/heyform" "tarball"
NODE_VERSION="22" NODE_MODULE="pnpm@$(grep -oP 'pnpm@\K[0-9.]+' /opt/heyform/Dockerfile)" setup_nodejs

msg_info "Building HeyForm"
cd /opt/heyform
HEYFORM_SKIP_SHARED_BUILD=1 $STD pnpm install --frozen-lockfile
cp packages/server/view/index.html packages/webapp/index.html
$STD pnpm build:shared
$STD pnpm --filter ./packages/server build
$STD pnpm --filter ./packages/webapp build
mkdir -p packages/server/static
cp -R packages/webapp/dist/static/. packages/server/static/
cp packages/webapp/dist/index.html packages/server/view/index.html
rm -rf ~/.cache/pnpm ~/.local/share/pnpm/store
msg_ok "Built HeyForm"

msg_info "Configuring HeyForm"
mkdir -p /opt/heyform_data/uploads
ln -sfn /opt/heyform_data/uploads /opt/heyform/packages/server/static/upload
cat <<EOF >/opt/heyform_data/.env
NODE_ENV=production
APP_HOMEPAGE_URL=https://${LOCAL_IP}
APP_LISTEN_HOSTNAME=127.0.0.1
APP_LISTEN_PORT=9157
TRUST_PROXY=loopback
ENABLE_GOOGLE_FONTS=false
SESSION_KEY=$(random_password 48)
FORM_ENCRYPTION_KEY=$(random_password 48)
INTEGRATION_ENCRYPTION_KEY=$(openssl rand -base64 32)
VERIFY_USER_EMAIL=false
MONGO_URI=mongodb://127.0.0.1:27017/heyform
REDIS_HOST=127.0.0.1
REDIS_PORT=6379
SMTP_FROM=
SMTP_HOST=
SMTP_PORT=465
SMTP_USER=
SMTP_PASSWORD=
EOF
chmod 600 /opt/heyform_data/.env
msg_ok "Configured HeyForm"

msg_info "Configuring Nginx"
create_self_signed_cert "heyform"
cat <<'EOF' >/etc/nginx/sites-available/heyform
server {
    listen 80 default_server;
    server_name _;
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl default_server;
    http2 on;
    server_name _;

    ssl_certificate /etc/ssl/heyform/heyform.crt;
    ssl_certificate_key /etc/ssl/heyform/heyform.key;

    client_max_body_size 20m;

    location / {
        proxy_pass http://127.0.0.1:9157;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection $http_connection;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
EOF
nginx_enable_site "heyform"
msg_ok "Configured Nginx"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/heyform.service
[Unit]
Description=HeyForm
After=network-online.target mongod.service redis-server.service
Wants=network-online.target
Requires=mongod.service redis-server.service

[Service]
Type=simple
WorkingDirectory=/opt/heyform/packages/server
EnvironmentFile=/opt/heyform_data/.env
ExecStart=/usr/bin/node scripts/start.js
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now redis-server heyform
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc
