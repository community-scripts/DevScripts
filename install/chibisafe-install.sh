#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://github.com/chibisafe/chibisafe

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

var_admin_pass="${var_admin_pass:-$(random_password)}"

msg_info "Installing Dependencies"
$STD apt install -y nginx
msg_ok "Installed Dependencies"

setup_ffmpeg
NODE_VERSION="26" setup_nodejs

fetch_and_deploy_gh_release "chibisafe" "chibisafe/chibisafe" "tarball"

msg_info "Building Chibisafe"
cd /opt/chibisafe
$STD yarn workspaces focus @chibisafe/next
NEXT_TELEMETRY_DISABLED=1 $STD yarn workspace @chibisafe/next build
cp -r packages/next/public packages/next/.next/standalone/packages/next/
cp -r packages/next/.next/static packages/next/.next/standalone/packages/next/.next/
$STD yarn workspaces focus @chibisafe/backend
$STD yarn workspace @chibisafe/backend generate
$STD yarn workspace @chibisafe/backend build
rm -rf packages/next/.next/cache
$STD yarn cache clean --all
msg_ok "Built Chibisafe"

msg_info "Configuring Chibisafe"
mkdir -p /opt/chibisafe_data/{database,uploads,logs}
ln -sfn /opt/chibisafe_data/database /opt/chibisafe/database
ln -sfn /opt/chibisafe_data/uploads /opt/chibisafe/uploads
ln -sfn /opt/chibisafe_data/logs /opt/chibisafe/logs
cat <<EOF >/opt/chibisafe_data/.env
NODE_ENV=production
HOST=127.0.0.1
PORT=8000
ADMIN_PASSWORD=${var_admin_pass}
EOF
chmod 600 /opt/chibisafe_data/.env
msg_ok "Configured Chibisafe"

msg_info "Creating Services"
cat <<EOF >/etc/systemd/system/chibisafe-backend.service
[Unit]
Description=Chibisafe Backend
After=network.target

[Service]
Type=simple
WorkingDirectory=/opt/chibisafe/packages/backend
EnvironmentFile=/opt/chibisafe_data/.env
Environment=NODE_PRESERVE_SYMLINKS=1
ExecStart=/usr/bin/node -r tsconfig-paths/register dist/main.js
TimeoutStopSec=10
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
cat <<EOF >/etc/systemd/system/chibisafe-frontend.service
[Unit]
Description=Chibisafe Frontend
After=network.target chibisafe-backend.service

[Service]
Type=simple
WorkingDirectory=/opt/chibisafe/packages/next/.next/standalone/packages/next
Environment=NODE_ENV=production
Environment=HOSTNAME=127.0.0.1
Environment=PORT=8001
Environment=BASE_API_URL=http://127.0.0.1:8000
ExecStart=/usr/bin/node --dns-result-order=ipv4first server.js
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now chibisafe-backend chibisafe-frontend
msg_ok "Created Services"

msg_info "Configuring Nginx"
cat <<'EOF' >/etc/nginx/sites-available/chibisafe
server {
    listen 80;
    server_name _;
    client_max_body_size 0;
    root /opt/chibisafe_data/uploads;

    proxy_http_version 1.1;
    proxy_set_header Host $http_host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_read_timeout 600s;
    proxy_send_timeout 600s;

    location ^~ /api/ {
        proxy_request_buffering off;
        proxy_pass http://127.0.0.1:8000;
    }

    location ^~ /docs {
        proxy_pass http://127.0.0.1:8000;
    }

    location = / {
        proxy_pass http://127.0.0.1:8001;
    }

    location ^~ /tmp/ {
        return 404;
    }

    location ^~ /quarantine/ {
        return 404;
    }

    location / {
        add_header Content-Security-Policy "sandbox; script-src 'none'; object-src 'none'; base-uri 'none'; form-action 'none'" always;
        add_header X-Content-Type-Options nosniff always;
        add_header Access-Control-Allow-Origin * always;
        try_files $uri $uri/index.html $uri/index.txt @frontend;
    }

    location @frontend {
        proxy_pass http://127.0.0.1:8001;
    }
}
EOF
nginx_enable_site "chibisafe"
msg_ok "Configured Nginx"

motd_ssh
customize
cleanup_lxc
