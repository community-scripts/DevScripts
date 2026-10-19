#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: a55uka (a55uka)
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://github.com/TheSpaghettiDetective/obico-server

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt install -y \
  libmagic1 \
  redis-server
systemctl enable -q --now redis-server
msg_ok "Installed Dependencies"

setup_ffmpeg

fetch_and_deploy_gh_branch "obico" "TheSpaghettiDetective/obico-server" "release" "/opt/obico"
PYTHON_VERSION="3.12" setup_uv

msg_info "Setting up Python Environments"
cd /opt/obico/backend
$STD uv venv --python 3.12 .venv
$STD uv pip install -p .venv/bin/python -r requirements.txt
# Pinned the same way as backend/Dockerfile.base for the moonraker metadata parser
$STD uv pip install -p .venv/bin/python importlib_metadata==8.2.0
cd /opt/obico/ml_api
$STD uv venv --python 3.12 .venv
# CPU inference stack, mirroring ml_api/Containerfile.cpu (onnxruntime 1.16.3 has no cp312 wheels)
$STD uv pip install -p .venv/bin/python -r requirements.txt onnxruntime==1.31.0 opencv-python-headless==4.12.0.88
msg_ok "Set up Python Environments"

msg_info "Installing Moonraker Metadata Library"
# Same pinned clone as backend/Dockerfile.base; gcode metadata parsing imports moonraker via PYTHONPATH
MOONRAKER_SHA=$(grep -oP 'checkout \K[a-f0-9]{40}' /opt/obico/backend/Dockerfile.base)
$STD git clone https://github.com/Arksine/moonraker.git /opt/moonraker
$STD git -C /opt/moonraker checkout "$MOONRAKER_SHA"
msg_ok "Installed Moonraker Metadata Library"

msg_info "Downloading Failure Detection Model"
mkdir -p /model_cache/ml_api/onnx
# Upstream's own checksum-verifying downloader, reading URL and sha256 from the repo's sidecar files
bash /opt/obico/ml_api/scripts/fetch_verified.sh "$(tr -d '\r' </opt/obico/ml_api/model/model-weights.onnx.url)" /model_cache/ml_api/onnx/model-weights.onnx 50000000 "$(tr -d '\r' </opt/obico/ml_api/model/model-weights.onnx.sha256)"
msg_ok "Downloaded Failure Detection Model"

msg_info "Configuring Obico"
# secrets.token_urlsafe() is exactly what `manage.py gen_site_secret` prints, without booting Django before the DB exists
DJANGO_SECRET_KEY=$(cd /opt/obico/backend && .venv/bin/python -c 'import secrets; print(secrets.token_urlsafe())' 2>/dev/null)
ML_API_TOKEN=$(random_password 32)
cat <<EOF >/opt/obico/.env
DJANGO_SECRET_KEY=${DJANGO_SECRET_KEY}
REDIS_URL=redis://127.0.0.1:6379
DATABASE_URL=sqlite:////opt/obico/backend/db.sqlite3
INTERNAL_MEDIA_HOST=http://127.0.0.1:3334
ML_API_HOST=http://127.0.0.1:3333
ML_API_TOKEN=${ML_API_TOKEN}
OCTOPRINT_TUNNEL_PORT_RANGE=0-0
VERSION=$(cat ~/.obico)
PYTHONPATH=/opt/moonraker
EOF
chmod 600 /opt/obico/.env
msg_ok "Configured Obico"

msg_info "Initializing Database"
set -a
source /opt/obico/.env
set +a
cd /opt/obico/backend
$STD .venv/bin/python manage.py migrate --noinput
$STD .venv/bin/python manage.py collectstatic --noinput
$STD .venv/bin/python manage.py site --add "${LOCAL_IP}:3334"
msg_ok "Initialized Database"

msg_info "Creating Services"
cat <<EOF >/etc/systemd/system/obico-ml-api.service
[Unit]
Description=Obico ML API
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/obico/ml_api
EnvironmentFile=/opt/obico/.env
# Bound to 0.0.0.0 because external clients (e.g. Bambuddy's Obico integration)
# call the ML API directly; ML_API_TOKEN from /opt/obico/.env gates every
# endpoint but the health check.
ExecStart=/opt/obico/ml_api/.venv/bin/gunicorn --bind 0.0.0.0:3333 --workers 1 --timeout 120 wsgi
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

cat <<EOF >/etc/systemd/system/obico-web.service
[Unit]
Description=Obico Web Server
Wants=network-online.target obico-ml-api.service
After=network-online.target redis-server.service obico-ml-api.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/obico/backend
EnvironmentFile=/opt/obico/.env
ExecStart=/opt/obico/backend/.venv/bin/daphne -b 0.0.0.0 -p 3334 config.routing:application
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

cat <<EOF >/etc/systemd/system/obico-tasks.service
[Unit]
Description=Obico Celery Worker
Wants=network-online.target
After=network-online.target redis-server.service obico-web.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/obico/backend
EnvironmentFile=/opt/obico/.env
ExecStart=/opt/obico/backend/.venv/bin/celery -A config worker --beat -l info -c 2 -Q realtime,celery
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now obico-ml-api obico-web obico-tasks
msg_ok "Created Services"

msg_info "Waiting for Obico to start"
for ((i = 1; i <= 45; i++)); do
  curl -fsS http://127.0.0.1:3334/hc/ >/dev/null 2>&1 && break
  sleep 2
done
if ! curl -fsS http://127.0.0.1:3334/hc/ >/dev/null 2>&1; then
  msg_error "Obico did not respond within 90s. Check 'journalctl -u obico-web -u obico-ml-api -u obico-tasks'"
  exit 150
fi
msg_ok "Obico is running"

motd_ssh
customize
cleanup_lxc
