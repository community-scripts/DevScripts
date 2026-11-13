#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://github.com/rivet-dev/rivet

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

RIVET_VERSION="${var_appversion:-$(get_latest_github_release "rivet-dev/rivet")}"
msg_info "Installing Rivet Engine ${RIVET_VERSION#v}"
mkdir -p /opt/rivet
curl_with_retry "https://releases.rivet.dev/rivet/${RIVET_VERSION#v}/engine/rivet-engine-$(arch_resolve "x86_64" "aarch64")-unknown-linux-musl" /opt/rivet/rivet-engine
chmod +x /opt/rivet/rivet-engine
cat <<EOF >~/.rivet
${RIVET_VERSION#v}
EOF
msg_ok "Installed Rivet Engine ${RIVET_VERSION#v}"

msg_info "Configuring Rivet Engine"
RIVET_TOKEN="${var_admin_token:-$(random_password 32)}"
mkdir -p /opt/rivet_data/log
cat <<EOF >/opt/rivet_data/config.json
{
  "auth": {
    "admin_token": "${RIVET_TOKEN}"
  },
  "storage": {
    "log_directory": "/opt/rivet_data/log",
    "auto_provision_partitions": 1,
    "balancing": { "enabled": false }
  },
  "object_storage": {
    "primary": { "file_system": { "path": "/opt/rivet_data/objects" } }
  }
}
EOF
chmod 600 /opt/rivet_data/config.json
msg_ok "Configured Rivet Engine"

msg_info "Creating Rivet Engine Service"
cat <<EOF >/etc/systemd/system/rivet.service
[Unit]
Description=Rivet Engine
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
ExecStart=/opt/rivet/rivet-engine --config /opt/rivet_data/config.json
Restart=always
RestartSec=5
LimitNOFILE=65536
TimeoutStopSec=660

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now rivet
msg_ok "Created Rivet Engine Service"

msg_info "Creating Default Node Pool"
$STD curl -fsS --retry 30 --retry-all-errors --retry-delay 2 -X PUT \
  -H "Authorization: Bearer ${RIVET_TOKEN}" -H "Content-Type: application/json" -d '{}' \
  "http://127.0.0.1:6420/pools/default?namespace=default"
msg_ok "Created Default Node Pool"

motd_ssh
customize
cleanup_lxc
