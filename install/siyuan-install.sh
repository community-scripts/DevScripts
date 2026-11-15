#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://github.com/siyuan-note/siyuan

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

fetch_and_deploy_gh_release "siyuan" "siyuan-note/siyuan" "prebuild" "latest" "/opt/siyuan" "siyuan-*-$(arch_resolve "linux" "linux-arm64").tar.gz"

msg_info "Removing SiYuan Desktop Files"
find /opt/siyuan -mindepth 1 -maxdepth 1 ! -name resources -exec rm -rf {} +
rm -rf /opt/siyuan/resources/app
msg_ok "Removed SiYuan Desktop Files"

msg_info "Configuring SiYuan"
mkdir -p /opt/siyuan_data/workspace
cat <<EOF >/opt/siyuan_data/.env
SIYUAN_WORKSPACE_PATH=/opt/siyuan_data/workspace
SIYUAN_ACCESS_AUTH_CODE=${var_auth_code:-$(random_password)}
EOF
chmod 600 /opt/siyuan_data/.env
msg_ok "Configured SiYuan"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/siyuan.service
[Unit]
Description=SiYuan
After=network.target

[Service]
Type=simple
EnvironmentFile=/opt/siyuan_data/.env
# Server mode: listen on all interfaces and require the access auth code
Environment=RUN_IN_CONTAINER=true
ExecStart=/opt/siyuan/resources/kernel/SiYuan-Kernel serve --port=6806
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now siyuan
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc
