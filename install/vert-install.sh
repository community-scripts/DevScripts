#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://github.com/VERT-sh/VERT

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

NODE_VERSION="24" NODE_MODULE="bun" setup_nodejs
fetch_and_deploy_gh_branch "vert" "VERT-sh/VERT" "main"

msg_info "Configuring VERT"
mkdir -p /opt/vert_data
cat <<EOF >/opt/vert_data/.env
PUB_ENV=production
PUB_HOSTNAME=${LOCAL_IP}
PUB_PLAUSIBLE_URL=
PUB_VERTD_URL=
PUB_DISABLE_ALL_EXTERNAL_REQUESTS=false
PUB_DISABLE_FAILURE_BLOCKS=false
PUB_DONATION_URL=https://donations.vert.sh
PUB_STRIPE_KEY=pk_live_51TlrPaFTPjkhEGBSu5Kwy5jJQYxcX5yUUHXiH5g7Xzvb0NKzDqbooc126HjlW35uUkfAgQN2ruEoCuyQynoxpKaA00ojFgQ116
EOF
ln -sf /opt/vert_data/.env /opt/vert/.env
msg_ok "Configured VERT"

msg_info "Building VERT"
cd /opt/vert
$STD bun install
$STD bun run build
rm -rf /opt/vert/node_modules /opt/vert/.svelte-kit ~/.bun/install/cache
msg_ok "Built VERT"

msg_info "Configuring Nginx"
create_self_signed_cert "vert"
cat <<'EOF' >/etc/nginx/sites-available/vert
server {
    listen 80 default_server;
    server_name _;
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl default_server;
    http2 on;
    server_name _;

    ssl_certificate /etc/ssl/vert/vert.crt;
    ssl_certificate_key /etc/ssl/vert/vert.key;

    root /opt/vert/build;
    index index.html;

    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    add_header Permissions-Policy "geolocation=(), microphone=(), camera=()" always;
    add_header Cross-Origin-Opener-Policy "same-origin" always;
    add_header Cross-Origin-Embedder-Policy "credentialless" always;

    location / {
        try_files $uri $uri/ /index.html;
    }

    error_page 404 /index.html;
}
EOF
nginx_enable_site "vert"
msg_ok "Configured Nginx"

motd_ssh
customize
cleanup_lxc
