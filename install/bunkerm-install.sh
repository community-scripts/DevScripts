#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://bunkerai.dev/

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt install -y \
  build-essential \
  mosquitto \
  mosquitto-clients \
  libmosquitto-dev \
  nginx \
  supervisor \
  python3 \
  python3-dev \
  python3-venv \
  python3-pip \
  libffi-dev \
  libssl-dev \
  gcc \
  openssl
msg_ok "Installed Dependencies"

NODE_VERSION="20" setup_nodejs

fetch_and_deploy_gh_release "bunkerm" "bunkeriot/BunkerM" "tarball"

msg_info "Setting up Python Environment"
python3 -m venv /opt/venv
/opt/venv/bin/pip install --upgrade pip >/dev/null 2>&1
$STD /opt/venv/bin/pip install --no-cache-dir \
  psutil \
  paho-mqtt \
  fastapi \
  python-dotenv \
  pydantic \
  pydantic-settings \
  "uvicorn[standard]" \
  flask \
  flask-cors \
  pytz \
  statistics \
  python-multipart \
  "passlib[bcrypt]" \
  python-jwt \
  PyJWT \
  slowapi \
  secure \
  python-decouple \
  starlette-context \
  structlog \
  python-json-logger \
  aiofiles \
  types-aiofiles \
  typing-extensions \
  "sqlalchemy[asyncio]>=2.0.30" \
  "aiosqlite>=0.20.0" \
  "alembic>=1.13.0" \
  "httpx>=0.27.0" \
  "numpy>=1.26.0" \
  "websockets>=12.0" \
  "apscheduler>=3.10.0" \
  cryptography \
  pyOpenSSL \
  "python-jose[cryptography]" \
  fastapi-jwt-auth \
  fastapi-limiter
msg_ok "Set up Python Environment"

msg_info "Building Frontend"
cd /opt/bunkerm/frontend
export NODE_OPTIONS="--max-old-space-size=4096"
$STD npm install
$STD npm install --no-save tailwindcss@3 autoprefixer tailwindcss-animate
if [[ -f postcss.config.js ]] && grep -q 'module\.exports' postcss.config.js; then
  mv postcss.config.js postcss.config.cjs
fi
$STD npm run build
unset NODE_OPTIONS
mkdir -p /usr/share/nginx/html
cp -r /opt/bunkerm/frontend/dist/. /usr/share/nginx/html/
rm -rf /frontend
cp -r /opt/bunkerm/frontend /frontend
rm -rf /frontend/node_modules
cd /frontend/src/auth
$STD npm install
msg_ok "Built Frontend"

msg_info "Setting up Application"
mkdir -p /app
cp -r /opt/bunkerm/backend/app/. /app/
touch /app/monitor/__init__.py
msg_ok "Set up Application"

msg_info "Configuring Mosquitto"
mkdir -p /etc/mosquitto/conf.d /var/lib/mosquitto/db /var/log/mosquitto /tmp/mosquitto_backups /tmp/dynsec_backups
cp /opt/bunkerm/backend/mosquitto/config/mosquitto.conf /etc/mosquitto/mosquitto.conf
cp -r /opt/bunkerm/backend/etc/mosquitto/conf.d/. /etc/mosquitto/conf.d/
cp /opt/bunkerm/backend/mosquitto/dynsec/dynamic-security.json /var/lib/mosquitto/dynamic-security.json
touch /etc/mosquitto/mosquitto_passwd
id -u mosquitto &>/dev/null || useradd -r -s /usr/sbin/nologin mosquitto
chown -R mosquitto:mosquitto /var/lib/mosquitto /var/log/mosquitto /etc/mosquitto
sed -i "s|^plugin /usr/lib/mosquitto_dynamic_security.so$|plugin $(dpkg -L mosquitto | grep '/mosquitto_dynamic_security.so$')|" /etc/mosquitto/mosquitto.conf
chmod 600 /etc/mosquitto/mosquitto_passwd
msg_ok "Configured Mosquitto"

msg_info "Configuring Nginx"
mkdir -p /run/nginx /etc/nginx/conf.d /var/log/nginx /var/lib/history
cp /opt/bunkerm/nginx.conf /etc/nginx/nginx.conf
cp /opt/bunkerm/default.conf /etc/nginx/conf.d/default.conf
sed -i 's/^user nginx;$/user www-data;/' /etc/nginx/nginx.conf
msg_ok "Configured Nginx"

msg_info "Configuring Supervisor"
mkdir -p /var/log/supervisor /var/log/api /etc/bunkerm /data
cp /opt/bunkerm/backend/supervisord.conf /etc/supervisor/conf.d/bunkerm.conf
msg_ok "Configured Supervisor"

msg_info "Creating Environment"
MQTT_USERNAME="bunker"
MQTT_PASSWORD=$(random_password 24)
JWT_SECRET=$(openssl rand -base64 48 | tr -dc 'a-zA-Z0-9' | cut -c1-48)
API_KEY=$(openssl rand -base64 48 | tr -dc 'a-zA-Z0-9' | cut -c1-48)
AUTH_SECRET=$(openssl rand -base64 48 | tr -dc 'a-zA-Z0-9' | cut -c1-48)
cat <<EOF >/etc/bunkerm/bunkerm.env
MQTT_BROKER=localhost
MQTT_PORT=1900
MQTT_USERNAME=${MQTT_USERNAME}
MQTT_PASSWORD=${MQTT_PASSWORD}
MOSQUITTO_ADMIN_USERNAME=${MQTT_USERNAME}
MOSQUITTO_ADMIN_PASSWORD=${MQTT_PASSWORD}
JWT_SECRET=${JWT_SECRET}
API_KEY=${API_KEY}
AUTH_SECRET=${AUTH_SECRET}
HOST_ADDRESS=${LOCAL_IP}
FRONTEND_URL=http://${LOCAL_IP}:2000
ALLOWED_ORIGINS=*
ALLOWED_HOSTS=*
RATE_LIMIT_PER_MINUTE=100
LOG_LEVEL=INFO
API_LOG_FILE=/var/log/api/api_activity.log
BROKER_LOG_PATH=/var/log/mosquitto/mosquitto.log
CLIENT_LOG_PATH=/var/log/api/api_activity.log
MOSQUITTO_PASSWD_PATH=/etc/mosquitto/mosquitto_passwd
MOSQUITTO_CONF_PATH=/etc/mosquitto/mosquitto.conf
MOSQUITTO_BACKUP_DIR=/tmp/mosquitto_backups
CONFIG_API_PORT=1005
DYNSEC_PATH=/var/lib/mosquitto/dynamic-security.json
DYNSEC_BACKUP_DIR=/tmp/dynsec_backups
MAX_UPLOAD_SIZE=10485760
PYTHONPATH=/app/monitor
NODE_ENV=production
BUNKERAI_API_KEY=
BUNKERAI_WS_URL=wss://api.bunkerai.dev/connect
EOF
cat <<EOF >/usr/share/nginx/html/config.js
window.__runtime_config__ = {
  API_URL: "http://${LOCAL_IP}:2000/api/monitor",
  DYNSEC_API_URL: "http://${LOCAL_IP}:2000/api/dynsec",
  AWS_BRIDGE_API_URL: "http://${LOCAL_IP}:2000/api/aws-bridge",
  MONITOR_API_URL: "http://${LOCAL_IP}:2000/api/monitor",
  EVENT_API_URL: "http://${LOCAL_IP}:2000/api/event",
  host: "${LOCAL_IP}"
};
EOF
msg_ok "Created Environment"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/bunkerm.service
[Unit]
Description=BunkerM MQTT Management Platform
After=network.target

[Service]
Type=simple
User=root
EnvironmentFile=/etc/bunkerm/bunkerm.env
ExecStart=/usr/bin/supervisord -c /etc/supervisor/conf.d/bunkerm.conf -n
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now bunkerm
# The dynsec file from upstream ships the admin client bunker/bunker
for _ in {1..30}; do
  mosquitto_ctrl -h 127.0.0.1 -p 1900 -u bunker -P bunker dynsec getClient bunker &>/dev/null && break
  sleep 2
done
$STD mosquitto_ctrl -h 127.0.0.1 -p 1900 -u bunker -P bunker dynsec setClientPassword bunker "$MQTT_PASSWORD"
systemctl restart bunkerm
{
  echo "BunkerM MQTT admin"
  echo "Username: bunker"
  echo "Password: ${MQTT_PASSWORD}"
} >~/bunkerm.creds
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc
