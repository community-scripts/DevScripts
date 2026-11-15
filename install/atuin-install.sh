#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://github.com/atuinsh/atuin

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

fetch_and_deploy_gh_release "atuin" "atuinsh/atuin" "prebuild" "latest" "/opt/atuin" "atuin-server-$(arch_resolve "x86_64" "aarch64")-unknown-linux-gnu.tar.gz"

msg_info "Configuring Atuin Server"
mkdir -p /opt/atuin_data
cat <<EOF >/opt/atuin_data/server.toml
host = "0.0.0.0"
port = 8888
open_registration = false
db_uri = "sqlite:///opt/atuin_data/atuin-server.db"
EOF
ln -sf /opt/atuin/atuin-server /usr/local/bin/atuin-server
msg_ok "Configured Atuin Server"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/atuin-server.service
[Unit]
Description=Atuin Sync Server
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
Environment=ATUIN_CONFIG_DIR=/opt/atuin_data
ExecStart=/opt/atuin/atuin-server start
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now atuin-server
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc
