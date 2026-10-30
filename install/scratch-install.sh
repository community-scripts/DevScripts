#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: ma-world
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/scratchfoundation/scratch-editor

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
  libcairo2-dev \
  libpango1.0-dev \
  libjpeg-dev \
  libgif-dev \
  librsvg2-dev \
  nginx
msg_ok "Installed Dependencies"

NODE_VERSION="24" setup_nodejs

fetch_and_deploy_gh_release "scratch-editor" "scratchfoundation/scratch-editor" "tarball"

msg_info "Building Scratch GUI (this can take several minutes)"
cd /opt/scratch-editor
export NODE_OPTIONS="--max-old-space-size=2560"
export PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1
$STD npm install
$STD npm run build
msg_ok "Built Scratch GUI"

msg_info "Configuring nginx"
rm -rf /var/www/scratch
cp -a /opt/scratch-editor/packages/scratch-gui/build /var/www/scratch
cat <<EOF >/etc/nginx/sites-available/scratch.conf
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _;
    root /var/www/scratch;
    index index.html;

    location / {
        try_files \$uri \$uri/ /index.html;
    }
}
EOF
nginx_enable_site scratch.conf
systemctl enable -q --now nginx
msg_ok "Configured nginx"

motd_ssh
customize
cleanup_lxc
