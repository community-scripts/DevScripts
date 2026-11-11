#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Jacob Ledbetter (CryoTheRenegade)
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://github.com/Suwayomi/Suwayomi-Server

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt install -y \
  libxss1 \
  libxext6 \
  libxrender1 \
  libxcomposite1 \
  libxdamage1 \
  libxkbcommon0 \
  libxtst6 \
  libxcursor1 \
  libglib2.0-0t64 \
  libnss3 \
  libdbus-1-3 \
  libpango-1.0-0 \
  libcairo2 \
  libasound2t64 \
  libatk-bridge2.0-0t64 \
  libcups2t64 \
  libdrm2 \
  libgbm1 \
  libegl1 \
  fonts-arphic-ukai \
  fonts-arphic-uming \
  fonts-ipafont-mincho \
  fonts-ipafont-gothic \
  fonts-unfonts-core \
  xvfb \
  xauth
msg_ok "Installed Dependencies"

JAVA_VERSION="21" setup_java

fetch_and_deploy_gh_release "suwayomi" "Suwayomi/Suwayomi-Server" "singlefile" "latest" "/opt/suwayomi" "Suwayomi-Server-v*.jar"

msg_info "Configuring Suwayomi"
mkdir -p /opt/suwayomi_data
cat <<EOF >/opt/suwayomi_data/server.conf
server.systemTrayEnabled = false
server.initialOpenInBrowserEnabled = false
EOF
msg_ok "Configured Suwayomi"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/suwayomi.service
[Unit]
Description=Suwayomi Server
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/suwayomi_data
ExecStart=/usr/bin/xvfb-run -a /usr/bin/java -Dsuwayomi.tachidesk.config.server.rootDir=/opt/suwayomi_data -jar /opt/suwayomi/suwayomi
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now suwayomi
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc
