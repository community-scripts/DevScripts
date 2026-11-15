#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://github.com/apache/superset

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt install -y libecpg-dev
msg_ok "Installed Dependencies"

PG_VERSION="17" setup_postgresql
PG_DB_NAME="superset" PG_DB_USER="superset" PG_DB_CREDS_FILE="/dev/null" setup_postgresql_db
PYTHON_VERSION="3.11" setup_uv

SUPERSET_VERSION="${var_appversion:-$(get_latest_github_release "apache/superset")}"
msg_info "Installing Apache Superset ${SUPERSET_VERSION}"
$STD uv venv --python 3.11 /opt/superset/.venv
# the wheel's own ranges resolve to releases upstream excludes (flask-limiter 4 drops rich, the CLI fails)
curl_with_retry "https://raw.githubusercontent.com/apache/superset/${SUPERSET_VERSION}/requirements/base.txt" /opt/superset/requirements.txt
sed -i '/^-e /d' /opt/superset/requirements.txt
$STD uv pip install --python /opt/superset/.venv/bin/python -r /opt/superset/requirements.txt "apache-superset[postgres]==${SUPERSET_VERSION}"
cat <<EOF >~/.superset
${SUPERSET_VERSION}
EOF
msg_ok "Installed Apache Superset ${SUPERSET_VERSION}"

msg_info "Configuring Apache Superset"
mkdir -p /opt/superset_data
cat <<EOF >/opt/superset_data/superset_config.py
SECRET_KEY = "$(random_password 50)"
SQLALCHEMY_DATABASE_URI = "postgresql+psycopg2://superset:${PG_DB_PASS}@127.0.0.1:5432/superset"
EOF
cat <<EOF >/opt/superset_data/.env
SUPERSET_CONFIG_PATH=/opt/superset_data/superset_config.py
SUPERSET_HOME=/opt/superset_data
SUPERSET_ENV=production
FLASK_APP=superset
SUPERSET_ADMIN_PASSWORD=${var_admin_pass:-$(random_password)}
EOF
chmod 600 /opt/superset_data/superset_config.py /opt/superset_data/.env
set -a && source /opt/superset_data/.env && set +a
$STD /opt/superset/.venv/bin/superset db upgrade
$STD /opt/superset/.venv/bin/superset fab create-admin --username admin --firstname Superset --lastname Admin --email admin@superset.local --password "${SUPERSET_ADMIN_PASSWORD}"
$STD /opt/superset/.venv/bin/superset init
msg_ok "Configured Apache Superset"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/superset.service
[Unit]
Description=Apache Superset
After=network.target postgresql.service
Wants=postgresql.service

[Service]
Type=simple
WorkingDirectory=/opt/superset_data
EnvironmentFile=/opt/superset_data/.env
ExecStart=/opt/superset/.venv/bin/gunicorn --bind 0.0.0.0:8088 --workers 2 --worker-class gthread --threads 20 --timeout 120 --limit-request-line 0 --limit-request-field_size 0 "superset.app:create_app()"
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now superset
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc
