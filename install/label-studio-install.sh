#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://github.com/HumanSignal/label-studio

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

PG_VERSION="17" setup_postgresql
PG_DB_NAME="labelstudio" PG_DB_USER="labelstudio" PG_DB_CREDS_FILE="/dev/null" setup_postgresql_db
PYTHON_VERSION="3.13" setup_uv

LABEL_STUDIO_VERSION="${var_appversion:-$(get_latest_github_release "HumanSignal/label-studio")}"
msg_info "Installing Label Studio ${LABEL_STUDIO_VERSION}"
$STD uv venv --python 3.13 /opt/label-studio/.venv
$STD uv pip install --python /opt/label-studio/.venv/bin/python "label-studio==${LABEL_STUDIO_VERSION}"
cat <<EOF >~/.label-studio
${LABEL_STUDIO_VERSION}
EOF
msg_ok "Installed Label Studio ${LABEL_STUDIO_VERSION}"

msg_info "Configuring Label Studio"
mkdir -p /opt/label-studio_data
cat <<EOF >/opt/label-studio_data/.env
LABEL_STUDIO_BASE_DATA_DIR=/opt/label-studio_data
LABEL_STUDIO_HOST=
DJANGO_DB=default
POSTGRE_NAME=labelstudio
POSTGRE_USER=labelstudio
POSTGRE_PASSWORD=${PG_DB_PASS}
POSTGRE_HOST=localhost
POSTGRE_PORT=5432
SECRET_KEY=$(random_password 50)
LABEL_STUDIO_DISABLE_SIGNUP_WITHOUT_LINK=true
LABEL_STUDIO_USERNAME=${var_admin_email:-admin@localhost}
LABEL_STUDIO_PASSWORD=${var_admin_pass:-$(random_password)}
COLLECT_ANALYTICS=false
SENTRY_DSN=
FRONTEND_SENTRY_DSN=
EOF
chmod 600 /opt/label-studio_data/.env
cd /opt/label-studio_data
set -a && source /opt/label-studio_data/.env && set +a
$STD /opt/label-studio/.venv/bin/label-studio init -q
msg_ok "Configured Label Studio"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/label-studio.service
[Unit]
Description=Label Studio
After=network.target postgresql.service
Wants=postgresql.service

[Service]
Type=simple
WorkingDirectory=/opt/label-studio_data
EnvironmentFile=/opt/label-studio_data/.env
ExecStart=/opt/label-studio/.venv/bin/label-studio start --no-browser --internal-host 0.0.0.0 --port 8080
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now label-studio
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc
