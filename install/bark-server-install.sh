#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Charlie Smith (chazkii)
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://github.com/Finb/bark-server

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

fetch_and_deploy_gh_release "bark-server" "Finb/bark-server" "singlefile" "latest" "/opt/bark-server" "bark-server_linux_$(arch_resolve "amd64" "armv8")"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/bark-server.service
[Unit]
Description=Bark Server
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/bark-server
Environment=BARK_SERVER_ADDRESS=0.0.0.0:8080
Environment=BARK_SERVER_DATA_DIR=/opt/bark-server
ExecStart=/opt/bark-server/bark-server
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now bark-server
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc
