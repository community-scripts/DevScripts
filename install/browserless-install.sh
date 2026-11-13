#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://github.com/browserless/browserless

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt install -y \
  dumb-init \
  unzip \
  xvfb \
  fontconfig \
  fonts-freefont-ttf \
  fonts-gfs-neohellenic \
  fonts-indic \
  fonts-ipafont-gothic \
  fonts-liberation \
  fonts-noto-cjk \
  fonts-roboto \
  fonts-thai-tlwg \
  fonts-wqy-zenhei \
  fonts-open-sans \
  fonts-crosextra-carlito \
  fonts-dejavu-core
msg_ok "Installed Dependencies"

fetch_and_deploy_gh_release "browserless" "browserless/browserless" "tarball"
NODE_VERSION="$(grep -oP 'ARG NODE_VERSION=v\K[0-9]+' /opt/browserless/docker/base/Dockerfile)" setup_nodejs

msg_info "Building Browserless"
cd /opt/browserless
cp fonts/*.ttf /usr/share/fonts/truetype/
cp fonts/fonts.conf /etc/fonts/local.conf
$STD fc-cache -f
$STD npm ci
rm -rf src/routes/{chrome,edge,firefox,webkit} # the routes upstream leaves out of its chromium image
$STD npm run build
$STD npm run build:function
$STD npm run install:debugger
$STD npm prune --omit=dev
msg_ok "Built Browserless"

msg_info "Installing Chromium"
$STD ./node_modules/playwright-core/cli.js install --with-deps chromium
$STD node scripts/install-playwright-ffmpeg.js
msg_ok "Installed Chromium"

msg_info "Configuring Browserless"
mkdir -p /opt/browserless_data
cat <<EOF >/opt/browserless_data/.env
HOST=0.0.0.0
PORT=3000
TOKEN=${var_browserless_token:-$(random_password 32)}
CONCURRENT=10
QUEUED=10
TIMEOUT=30000
NODE_ENV=production
EOF
chmod 600 /opt/browserless_data/.env
msg_ok "Configured Browserless"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/browserless.service
[Unit]
Description=Browserless
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=/opt/browserless
EnvironmentFile=/opt/browserless_data/.env
ExecStart=/opt/browserless/scripts/start.sh
KillMode=mixed
TimeoutStopSec=30
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now browserless
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc
