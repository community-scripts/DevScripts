#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: vavallee (vavallee)
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://github.com/vavallee/bindery

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

fetch_and_deploy_gh_release "bindery" "vavallee/bindery" "prebuild" "latest" "/opt/bindery" "bindery_*_linux_$(arch_resolve "amd64" "arm64").tar.gz"

msg_info "Configuring Bindery"
mkdir -p /opt/bindery_data /books /downloads
cat <<EOF2 >/opt/bindery_data/.env
BINDERY_PORT=8787
BINDERY_DB_PATH=/opt/bindery_data/bindery.db
BINDERY_DATA_DIR=/opt/bindery_data
BINDERY_LIBRARY_DIR=/books
BINDERY_DOWNLOAD_DIR=/downloads
EOF2
msg_ok "Configured Bindery"

msg_info "Creating Service"
cat <<EOF2 >/etc/systemd/system/bindery.service
[Unit]
Description=Bindery
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/bindery
EnvironmentFile=/opt/bindery_data/.env
ExecStart=/opt/bindery/bindery
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF2
systemctl enable -q --now bindery
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc
