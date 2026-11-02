#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: TechJeeper (TechJeeper)
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://printventory.com | https://github.com/TechJeeper/Printventory

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt install -y \
  g++ \
  make \
  python3 \
  xvfb \
  dbus \
  chromium \
  chromium-sandbox \
  ca-certificates \
  fonts-liberation \
  libappindicator3-1 \
  libasound2 \
  libatk-bridge2.0-0 \
  libatk1.0-0 \
  libc6 \
  libcairo2 \
  libcups2 \
  libdbus-1-3 \
  libexpat1 \
  libfontconfig1 \
  libgbm1 \
  libgcc1 \
  libglib2.0-0 \
  libgtk-3-0 \
  libnspr4 \
  libnss3 \
  libpango-1.0-0 \
  libpangocairo-1.0-0 \
  libstdc++6 \
  libx11-6 \
  libx11-xcb1 \
  libxcb1 \
  libxcomposite1 \
  libxcursor1 \
  libxdamage1 \
  libxext6 \
  libxfixes3 \
  libxi6 \
  libxrandr2 \
  libxrender1 \
  libxss1 \
  libxtst6 \
  lsb-release \
  wget \
  xdg-utils
msg_ok "Installed Dependencies"

NODE_VERSION="22" setup_nodejs

# Upstream publishes no GitHub Releases yet — deploy from main (see AGENTS.md branch helpers).
fetch_and_deploy_gh_branch "printventory" "TechJeeper/Printventory" "main"

msg_info "Installing Printventory (Patience)"
cd /opt/printventory
$STD npm install --ignore-scripts
$STD npx @electron/rebuild --version="$(node -p 'require("electron/package.json").version')" || $STD npx electron-builder install-app-deps
chmod +x /opt/printventory/scripts/run-server.sh
mkdir -p /root/.config/printventory
msg_ok "Installed Printventory"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/printventory.service
[Unit]
Description=Printventory Server Mode
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/printventory
Environment=DISPLAY=:99
Environment=PUPPETEER_SKIP_CHROMIUM_DOWNLOAD=true
Environment=PUPPETEER_EXECUTABLE_PATH=/usr/bin/chromium
Environment=DCONF_DISABLE=1
Environment=GIO_USE_VFS=local
Environment=GIO_USE_VOLUME_MONITOR=unix
Environment=DBUS_FATAL_WARNINGS=0
Environment=PRINTVENTORY_GPU=swiftshader
ExecStart=/opt/printventory/scripts/run-server.sh
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now printventory
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc
