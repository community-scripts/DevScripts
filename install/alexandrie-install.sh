#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://github.com/Smaug6739/Alexandrie

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt install -y nginx
msg_ok "Installed Dependencies"

setup_go
NODE_VERSION="24" NODE_MODULE="bun" setup_nodejs
setup_mariadb
MARIADB_DB_NAME="alexandrie" MARIADB_DB_USER="alexandrie" MARIADB_DB_CREDS_FILE="/dev/null" setup_mariadb_db

fetch_and_deploy_gh_release "rustfs" "rustfs/rustfs" "prebuild" "latest" "/opt/rustfs" "rustfs-linux-$(arch_resolve x86_64 aarch64)-gnu-*.zip"
chmod +x /opt/rustfs/rustfs
fetch_and_deploy_gh_release "alexandrie" "Smaug6739/Alexandrie" "tarball"

msg_info "Building Alexandrie Backend"
cd /opt/alexandrie/backend
CGO_ENABLED=0 $STD go build -o alexandrie .
$STD go clean -cache -modcache
msg_ok "Built Alexandrie Backend"

msg_info "Building Alexandrie Frontend"
cd /opt/alexandrie/frontend
$STD bun install --frozen-lockfile
NODE_ENV=production $STD bun run build
rm -rf node_modules .nuxt ~/.bun/install/cache
msg_ok "Built Alexandrie Frontend"

msg_info "Configuring Alexandrie"
mkdir -p /opt/alexandrie_data/storage
S3_ACCESS_KEY=$(random_password 20)
S3_SECRET_KEY=$(random_password 40)
cat <<EOF >/opt/alexandrie_data/.env
BACKEND_PORT=8201
GIN_MODE=release
JWT_SECRET=$(random_password 64)
FRONTEND_URL=http://${LOCAL_IP}
COOKIE_DOMAIN=
ALLOW_UNSECURE=true
CONFIG_DISABLE_SIGNUP=false
CONFIG_DISABLE_NATIVE_LOGIN=false

DATABASE_HOST=127.0.0.1
DATABASE_PORT=3306
DATABASE_NAME=${MARIADB_DB_NAME}
DATABASE_USER=${MARIADB_DB_USER}
DATABASE_PASSWORD=${MARIADB_DB_PASS}

MINIO_ENDPOINT=127.0.0.1:9000
MINIO_PUBLIC_URL=http://${LOCAL_IP}
MINIO_SECURE=false
MINIO_ACCESSKEY=${S3_ACCESS_KEY}
MINIO_SECRETKEY=${S3_SECRET_KEY}
MINIO_BUCKET=alexandrie

SMTP_HOST=
SMTP_MAIL=
SMTP_MAIL_FROM=
SMTP_PASSWORD=

NUXT_PUBLIC_BASE_API=http://${LOCAL_IP}
NUXT_PUBLIC_BASE_CDN=http://${LOCAL_IP}
NUXT_PUBLIC_BASE_URL=http://${LOCAL_IP}
NUXT_PUBLIC_CDN_ENDPOINT=/alexandrie/
NUXT_PUBLIC_CONFIG_DISABLE_SIGNUP_PAGE=false
NUXT_PUBLIC_CONFIG_DISABLE_LANDING_PAGE=false

RUSTFS_ACCESS_KEY=${S3_ACCESS_KEY}
RUSTFS_SECRET_KEY=${S3_SECRET_KEY}
RUSTFS_VOLUMES=/opt/alexandrie_data/storage
RUSTFS_ADDRESS=127.0.0.1:9000
RUSTFS_CONSOLE_ENABLE=false
RUSTFS_OBS_LOGGER_LEVEL=error
EOF
chmod 600 /opt/alexandrie_data/.env
cat <<EOF >/etc/nginx/sites-available/alexandrie
server {
    listen 80;
    server_name _;
    client_max_body_size 1G;

    location /api/ {
        proxy_pass http://127.0.0.1:8201;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    location ~ ^/alexandrie(-backups)?/ {
        proxy_pass http://127.0.0.1:9000;
        proxy_set_header Host \$host;
        proxy_buffering off;
    }

    location / {
        proxy_pass http://127.0.0.1:8200;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF
nginx_enable_site "alexandrie"
msg_ok "Configured Alexandrie"

msg_info "Creating Services"
cat <<EOF >/etc/systemd/system/rustfs.service
[Unit]
Description=RustFS Object Storage for Alexandrie
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
WorkingDirectory=/opt/alexandrie_data
EnvironmentFile=/opt/alexandrie_data/.env
ExecStart=/opt/rustfs/rustfs
Restart=on-failure
RestartSec=5
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF
cat <<EOF >/etc/systemd/system/alexandrie-backend.service
[Unit]
Description=Alexandrie Backend
After=network-online.target mariadb.service rustfs.service
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=/opt/alexandrie/backend
EnvironmentFile=/opt/alexandrie_data/.env
ExecStart=/opt/alexandrie/backend/alexandrie
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
cat <<EOF >/etc/systemd/system/alexandrie-frontend.service
[Unit]
Description=Alexandrie Frontend
After=network-online.target alexandrie-backend.service

[Service]
Type=simple
WorkingDirectory=/opt/alexandrie/frontend
EnvironmentFile=/opt/alexandrie_data/.env
Environment=NODE_ENV=production
Environment=HOST=127.0.0.1
Environment=PORT=8200
ExecStart=/usr/bin/node .output/server/index.mjs
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now rustfs alexandrie-backend alexandrie-frontend
msg_ok "Created Services"

motd_ssh
customize
cleanup_lxc
