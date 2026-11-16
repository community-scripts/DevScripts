#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://github.com/CapSoftware/Cap

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

var_cap_url="${var_cap_url:-https://${LOCAL_IP}}"

msg_info "Installing Dependencies"
$STD apt install -y nginx
msg_ok "Installed Dependencies"

setup_ffmpeg
setup_mysql
MYSQL_DB_NAME="cap" MYSQL_DB_USER="cap" MYSQL_DB_CREDS_FILE="/dev/null" setup_mysql_db

fetch_and_deploy_gh_release "rustfs" "rustfs/rustfs" "prebuild" "latest" "/opt/rustfs" "rustfs-linux-$(arch_resolve "x86_64" "aarch64")-gnu-v*.zip"
fetch_and_deploy_gh_release "cap" "CapSoftware/Cap" "tarball" "latest" "/opt/cap" "" "cap-v"
NODE_VERSION="24" NODE_MODULE="$(jq -r '.packageManager' /opt/cap/package.json)" setup_nodejs

msg_info "Configuring Cap"
mkdir -p /opt/cap_data/{s3,workflow}
S3_ACCESS_KEY=$(random_password 20)
S3_SECRET_KEY=$(random_password 40)
cat <<EOF >/opt/cap_data/.env
NODE_ENV=production
DATABASE_URL=mysql://cap:${MYSQL_DB_PASS}@127.0.0.1:3306/cap
WEB_URL=${var_cap_url}
NEXTAUTH_URL=${var_cap_url}
NEXTAUTH_SECRET=$(openssl rand -hex 32)
DATABASE_ENCRYPTION_KEY=$(openssl rand -hex 32)
MEDIA_SERVER_URL=http://127.0.0.1:3456
MEDIA_SERVER_WEBHOOK_URL=http://127.0.0.1:3000
MEDIA_SERVER_WEBHOOK_SECRET=$(openssl rand -hex 32)
WORKFLOW_LOCAL_DATA_DIR=/opt/cap_data/workflow
WORKFLOW_LOCAL_BASE_URL=http://127.0.0.1:3000
CAP_AWS_BUCKET=cap
CAP_AWS_REGION=us-east-1
CAP_AWS_ACCESS_KEY=${S3_ACCESS_KEY}
CAP_AWS_SECRET_KEY=${S3_SECRET_KEY}
S3_PUBLIC_ENDPOINT=${var_cap_url}
S3_INTERNAL_ENDPOINT=http://127.0.0.1:9000
S3_PATH_STYLE=true
RUSTFS_ACCESS_KEY=${S3_ACCESS_KEY}
RUSTFS_SECRET_KEY=${S3_SECRET_KEY}
RUSTFS_VOLUMES=/opt/cap_data/s3
RUSTFS_ADDRESS=127.0.0.1:9000
RUSTFS_CONSOLE_ENABLE=false
RESEND_API_KEY=${var_resend_api_key:-}
RESEND_FROM_DOMAIN=${var_resend_from_domain:-}
EOF
chmod 600 /opt/cap_data/.env
msg_ok "Configured Cap"

msg_info "Building Cap"
cd /opt/cap
$STD bun install --frozen-lockfile
NEXT_PUBLIC_DOCKER_BUILD=true NEXT_PUBLIC_WEB_URL="${var_cap_url}" NEXT_TELEMETRY_DISABLED=1 $STD bun run build:web
cp -r apps/web/.next/static apps/web/.next/standalone/apps/web/.next/
cp -r apps/web/public apps/web/.next/standalone/apps/web/
cp -r packages/database/migrations apps/web/.next/standalone/apps/web/
rm -rf apps/web/.next/cache ~/.bun/install/cache ~/.npm
msg_ok "Built Cap"

msg_info "Configuring Nginx"
create_self_signed_cert "cap"
cat <<'EOF' >/etc/nginx/sites-available/cap
server {
    listen 80 default_server;
    server_name _;
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl default_server;
    http2 on;
    server_name _;

    ssl_certificate /etc/ssl/cap/cap.crt;
    ssl_certificate_key /etc/ssl/cap/cap.key;

    client_max_body_size 0;
    proxy_request_buffering off;

    location = /cap {
        proxy_pass http://127.0.0.1:9000;
        proxy_set_header Host $http_host;
    }

    location /cap/ {
        proxy_pass http://127.0.0.1:9000;
        proxy_set_header Host $http_host;
        proxy_buffering off;
    }

    location / {
        proxy_pass http://127.0.0.1:3000;
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
nginx_enable_site "cap"
msg_ok "Configured Nginx"

msg_info "Creating Services"
cat <<EOF >/etc/systemd/system/cap-rustfs.service
[Unit]
Description=Cap Storage (RustFS)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=/opt/cap_data
EnvironmentFile=/opt/cap_data/.env
ExecStart=/opt/rustfs/rustfs
Restart=on-failure
RestartSec=5
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF
cat <<EOF >/etc/systemd/system/cap-media-server.service
[Unit]
Description=Cap Media Server
After=network-online.target

[Service]
Type=simple
WorkingDirectory=/opt/cap/apps/media-server
EnvironmentFile=/opt/cap_data/.env
Environment=PORT=3456
ExecStart=/usr/bin/bun run src/index.ts
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
cat <<EOF >/etc/systemd/system/cap-web.service
[Unit]
Description=Cap Web
After=network-online.target mysql.service cap-rustfs.service cap-media-server.service
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=/opt/cap/apps/web/.next/standalone/apps/web
EnvironmentFile=/opt/cap_data/.env
Environment=PORT=3000
Environment=HOSTNAME=127.0.0.1
ExecStart=/usr/bin/node server.js
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now cap-rustfs cap-media-server cap-web
msg_ok "Created Services"

motd_ssh
customize
cleanup_lxc
