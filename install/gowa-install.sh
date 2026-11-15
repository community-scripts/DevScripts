#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://github.com/aldinokemal/go-whatsapp-web-multidevice

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt install -y \
  nginx \
  webp \
  poppler-utils
msg_ok "Installed Dependencies"

setup_ffmpeg

fetch_and_deploy_gh_release "gowa" "aldinokemal/go-whatsapp-web-multidevice" "prebuild" "latest" "/opt/gowa" "whatsapp_*_linux_$(arch_resolve).zip"

msg_info "Configuring GOWA"
mkdir -p /opt/gowa_data/storages/ui
# GOWA's own dashboard download uses the rate-limited GitHub API; seed it
curl_with_retry "https://github.com/aldinokemal/gowa-ui/releases/latest/download/gowa-ui.html" /opt/gowa_data/storages/ui/index.html
cat <<EOF >/opt/gowa_data/.env
APP_PORT=3000
APP_HOST=0.0.0.0
APP_TRUSTED_PROXIES=127.0.0.1
APP_BASIC_AUTH=${var_admin_user:-admin}:${var_admin_pass:-$(random_password)}
WHATSAPP_WEBHOOK_SECRET=$(openssl rand -hex 32)
EOF
chmod 600 /opt/gowa_data/.env
msg_ok "Configured GOWA"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/gowa.service
[Unit]
Description=GOWA WhatsApp API
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=/opt/gowa_data
ExecStart=/opt/gowa/linux-$(arch_resolve) rest
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now gowa
msg_ok "Created Service"

msg_info "Configuring Nginx"
create_self_signed_cert "gowa"
cat <<EOF >/etc/nginx/sites-available/gowa
server {
    listen 80;
    server_name _;
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl;
    server_name _;
    ssl_certificate /etc/ssl/gowa/gowa.crt;
    ssl_certificate_key /etc/ssl/gowa/gowa.key;
    client_max_body_size 100m;

    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_read_timeout 1h;
    }
}
EOF
nginx_enable_site "gowa"
msg_ok "Configured Nginx"

motd_ssh
customize
cleanup_lxc
