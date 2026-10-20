#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Josua Blejeru (josuablejeru)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/nisshi-io/nisshi

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

fetch_and_deploy_gh_release "nisshi" "nisshi-io/nisshi" "prebuild" "latest" "/opt/nisshi" "nisshi-$(arch_resolve "x86_64" "aarch64")-unknown-linux-*.tar.gz"

msg_info "Configuring Nisshi"
mkdir -p /opt/nisshi_data
cat <<EOF >/opt/nisshi_data/.env
CLUSTER_ID=nisshi
LISTENER_URL=tcp://0.0.0.0:9092
ADVERTISED_LISTENER_URL=tcp://${LOCAL_IP}:9092
STORAGE_ENGINE=sqlite://nisshi.db
RUST_LOG=warn
EOF
msg_ok "Configured Nisshi"

msg_info "Creating Service"
# The SQLite path is relative to WorkingDirectory, which keeps the database
# in /opt/nisshi_data and out of /opt/nisshi, which an update wipes.
cat <<EOF >/etc/systemd/system/nisshi.service
[Unit]
Description=Nisshi Service
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/nisshi_data
EnvironmentFile=/opt/nisshi_data/.env
ExecStart=/opt/nisshi/bin/nisshi broker
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now nisshi
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc
