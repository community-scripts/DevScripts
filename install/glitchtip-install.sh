#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://gitlab.com/glitchtip/glitchtip-backend

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

PG_VERSION="18" setup_postgresql
PG_DB_NAME="glitchtip" PG_DB_USER="glitchtip" PG_DB_CREDS_FILE="/dev/null" setup_postgresql_db
PYTHON_VERSION="3.14" setup_uv

msg_info "Tuning PostgreSQL"
cat <<EOF >/etc/postgresql/18/main/conf.d/glitchtip.conf
max_locks_per_transaction = 512
EOF
systemctl restart postgresql
msg_ok "Tuned PostgreSQL"

fetch_and_deploy_gl_release "glitchtip" "glitchtip/glitchtip-backend" "tarball"
fetch_and_deploy_from_url "https://gitlab.com/api/v4/projects/15449363/jobs/artifacts/v$(cat ~/.glitchtip)/download?job=build-assets" "/opt/glitchtip/frontend"

msg_info "Setting up GlitchTip"
mv /opt/glitchtip/frontend/glitchtip-frontend/browser /opt/glitchtip/dist
rm -rf /opt/glitchtip/frontend
cd /opt/glitchtip
$STD uv sync --frozen --no-dev --no-install-project --python 3.14
mkdir -p /opt/glitchtip_data
cat <<EOF >/opt/glitchtip_data/.env
SECRET_KEY=$(random_password 64)
DATABASE_URL=postgres://glitchtip:${PG_DB_PASS}@localhost:5432/glitchtip
VALKEY_URL=
GLITCHTIP_DOMAIN=http://${LOCAL_IP}:8000
EMAIL_URL=consolemail://
DEFAULT_FROM_EMAIL=glitchtip@localhost
ENABLE_USER_REGISTRATION=False
MEDIA_ROOT=/opt/glitchtip_data
GLITCHTIP_VERSION=$(cat ~/.glitchtip)
DJANGO_SUPERUSER_EMAIL=${var_admin_email:-admin@example.com}
DJANGO_SUPERUSER_PASSWORD=${var_admin_pass:-$(random_password)}
EOF
chmod 600 /opt/glitchtip_data/.env
set -a && source /opt/glitchtip_data/.env && set +a
$STD .venv/bin/python manage.py collectstatic --noinput
$STD .venv/bin/python manage.py migrate --noinput
$STD .venv/bin/python manage.py createsuperuser --noinput
msg_ok "Set up GlitchTip"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/glitchtip.service
[Unit]
Description=GlitchTip
After=network.target postgresql.service
Wants=postgresql.service

[Service]
Type=simple
WorkingDirectory=/opt/glitchtip
EnvironmentFile=/opt/glitchtip_data/.env
Environment=PATH=/opt/glitchtip/.venv/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
ExecStart=/opt/glitchtip/bin/run-all-in-one.sh
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now glitchtip
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc
