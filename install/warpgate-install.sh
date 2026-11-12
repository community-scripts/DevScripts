#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://github.com/warp-tech/warpgate

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

fetch_and_deploy_gh_release "warpgate" "warp-tech/warpgate" "singlefile" "latest" "/opt/warpgate" "warpgate-v*-$(arch_resolve "x86_64" "arm64")-linux"

msg_info "Configuring Warpgate"
ADMIN_PASS="${var_admin_pass:-$(random_password)}"
mkdir -p /opt/warpgate_data
cat <<EOF >/opt/warpgate_data/.env
WARPGATE_ADMIN_USER=admin
WARPGATE_ADMIN_PASSWORD=${ADMIN_PASS}
EOF
chmod 600 /opt/warpgate_data/.env
WARPGATE_ADMIN_PASSWORD="$ADMIN_PASS" $STD /opt/warpgate/warpgate --config /opt/warpgate_data/warpgate.yaml unattended-setup \
  --data-path /opt/warpgate_data \
  --http-port 8888 \
  --ssh-port 2222 \
  --mysql-port 33306 \
  --postgres-port 55432 \
  --kubernetes-port 8443 \
  --record-sessions
# A host kernel booted without IPv6 cannot bind [::]
[[ -d /proc/sys/net/ipv6 ]] || sed -i "s/'\[::\]:/'0.0.0.0:/" /opt/warpgate_data/warpgate.yaml
msg_ok "Configured Warpgate"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/warpgate.service
[Unit]
Description=Warpgate
After=network.target
StartLimitIntervalSec=0

[Service]
Type=notify
ExecStart=/opt/warpgate/warpgate --config /opt/warpgate_data/warpgate.yaml run
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now warpgate
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc
