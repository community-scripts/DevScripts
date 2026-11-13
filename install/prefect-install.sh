#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://github.com/PrefectHQ/prefect

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt install -y git
msg_ok "Installed Dependencies"

PYTHON_VERSION="3.12" setup_uv
check_for_gh_release "prefect-server" "PrefectHQ/prefect" "${var_appversion:-}" "" "3."

msg_info "Installing Prefect ${CHECK_UPDATE_RELEASE}"
$STD uv venv --python 3.12 /opt/prefect/.venv
$STD uv pip install --python /opt/prefect/.venv/bin/python "prefect==${CHECK_UPDATE_RELEASE}"
cat <<EOF >~/.prefect-server
${CHECK_UPDATE_RELEASE}
EOF
msg_ok "Installed Prefect ${CHECK_UPDATE_RELEASE}"

msg_info "Configuring Prefect"
PREFECT_AUTH="${var_prefect_user:-admin}:${var_prefect_password:-$(random_password)}"
mkdir -p /opt/prefect_data /root/.prefect
cat <<EOF >/opt/prefect_data/.env
PREFECT_HOME=/opt/prefect_data
PREFECT_SERVER_API_HOST=0.0.0.0
PREFECT_SERVER_API_PORT=4200
PREFECT_SERVER_UI_API_URL=/api
PREFECT_SERVER_API_AUTH_STRING=${PREFECT_AUTH}
PREFECT_SERVER_ANALYTICS_ENABLED=false
PREFECT_API_URL=http://127.0.0.1:4200/api
PREFECT_API_AUTH_STRING=${PREFECT_AUTH}
EOF
chmod 600 /opt/prefect_data/.env
cat <<EOF >/root/.prefect/profiles.toml
active = "local"

[profiles.local]
PREFECT_API_URL = "http://127.0.0.1:4200/api"
PREFECT_API_AUTH_STRING = "${PREFECT_AUTH}"
EOF
chmod 600 /root/.prefect/profiles.toml
ln -sf /opt/prefect/.venv/bin/prefect /usr/local/bin/prefect
msg_ok "Configured Prefect"

msg_info "Creating Services"
cat <<EOF >/etc/systemd/system/prefect-server.service
[Unit]
Description=Prefect Server
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=/opt/prefect_data
EnvironmentFile=/opt/prefect_data/.env
ExecStart=/opt/prefect/.venv/bin/prefect server start
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
cat <<EOF >/etc/systemd/system/prefect-worker.service
[Unit]
Description=Prefect Worker
After=prefect-server.service
Wants=prefect-server.service

[Service]
Type=simple
WorkingDirectory=/opt/prefect_data
EnvironmentFile=/opt/prefect_data/.env
ExecStart=/opt/prefect/.venv/bin/prefect worker start --pool default --type process
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now prefect-server prefect-worker
msg_ok "Created Services"

motd_ssh
customize
cleanup_lxc
