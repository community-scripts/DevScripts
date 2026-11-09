#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://github.com/stoatchat/stoatchat

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt install -y \
  pkg-config \
  libdav1d-dev \
  libssl-dev \
  build-essential \
  git \
  redis-server \
  rabbitmq-server \
  nginx
msg_ok "Installed Dependencies"

setup_mongodb

msg_info "Configuring RabbitMQ"
systemctl enable -q --now rabbitmq-server
until rabbitmqctl status &>/dev/null; do sleep 1; done
RABBIT_PASS=$(random_password 24)
$STD rabbitmqctl add_user rabbituser "$RABBIT_PASS"
$STD rabbitmqctl set_permissions -p / rabbituser ".*" ".*" ".*"
msg_ok "Configured RabbitMQ"

setup_rust

fetch_and_deploy_gh_release "stoatchat" "stoatchat/stoatchat" "tarball"

msg_info "Building Backend (Patience)"
cd /opt/stoatchat
CARGO_PROFILE_RELEASE_LTO=thin \
  $STD cargo build --release --bins -j 2
msg_ok "Built Backend"

NODE_VERSION="22" setup_nodejs

msg_info "Installing pnpm"
$STD corepack enable pnpm
$STD corepack prepare pnpm@11.3.0 --activate
msg_ok "Installed pnpm"

msg_info "Cloning Web Frontend"
FORWEB_VERSION=$(get_latest_github_release "stoatchat/for-web")
$STD git clone --recursive "https://github.com/stoatchat/for-web" /opt/stoatchat-web
$STD git -C /opt/stoatchat-web checkout "$FORWEB_VERSION"
$STD git -C /opt/stoatchat-web submodule update --init --recursive
msg_ok "Cloned Web Frontend"

msg_info "Building Web Frontend"
cd /opt/stoatchat-web
$STD pnpm install --frozen-lockfile
$STD pnpm --filter stoat.js build
$STD pnpm --filter solid-livekit-components build
$STD pnpm --filter "@lingui-solid/babel-plugin-lingui-macro" build
$STD pnpm --filter "@lingui-solid/babel-plugin-extract-messages" build
$STD pnpm --filter client exec lingui compile --typescript
$STD pnpm --filter client exec node scripts/copyAssets.mjs
$STD pnpm --filter client exec panda codegen
VITE_API_URL="https://${LOCAL_IP}/api" \
  VITE_HOST="${LOCAL_IP}" \
  $STD pnpm --filter client exec vite build
msg_ok "Built Web Frontend"

msg_info "Installing Garage"
GARAGE_VERSION=$(curl -fsSL https://api.github.com/repos/deuxfleurs-org/garage/tags | jq -r '.[0].name')
curl -fsSL "https://garagehq.deuxfleurs.fr/_releases/${GARAGE_VERSION}/x86_64-unknown-linux-musl/garage" -o /usr/local/bin/garage
chmod +x /usr/local/bin/garage
echo "${GARAGE_VERSION}" >~/.garage
mkdir -p /var/lib/garage/{data,meta}
RPC_SECRET=$(openssl rand -hex 32)
ADMIN_TOKEN=$(openssl rand -base64 32)
cat <<EOF >/etc/garage.toml
metadata_dir = "/var/lib/garage/meta"
data_dir = "/var/lib/garage/data"
db_engine = "sqlite"
replication_factor = 1

rpc_bind_addr = "[::]:3901"
rpc_public_addr = "127.0.0.1:3901"
rpc_secret = "${RPC_SECRET}"

[s3_api]
s3_region = "garage"
api_bind_addr = "[::]:3900"
root_domain = ".s3.garage.localhost"

[s3_web]
bind_addr = "[::]:3902"
root_domain = ".web.garage.localhost"
index = "index.html"

[admin]
api_bind_addr = "[::]:3903"
admin_token = "${ADMIN_TOKEN}"
EOF
cat <<EOF >/etc/systemd/system/garage.service
[Unit]
Description=Garage Object Storage
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/var/lib/garage
ExecStart=/usr/local/bin/garage -c /etc/garage.toml server
Restart=on-failure
RestartSec=5
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now garage
msg_ok "Installed Garage"

msg_info "Configuring Garage Bucket"
until garage status &>/dev/null; do sleep 1; done
NODE_ID=$(garage status 2>/dev/null | awk '/^[0-9a-f]/{print $1; exit}')
$STD garage layout assign -z dc1 -c 1G "${NODE_ID}"
$STD garage layout apply --version 1
$STD garage key create stoatchat-app-key
GARAGE_ACCESS_KEY=$(garage key info stoatchat-app-key | awk '/Key ID:/{print $3}')
GARAGE_SECRET_KEY=$(garage key info stoatchat-app-key | awk '/Secret key:/{print $3}')
$STD garage bucket create revolt-uploads
$STD garage bucket allow --read --write --owner revolt-uploads --key stoatchat-app-key
msg_ok "Configured Garage Bucket"

FILES_ENCRYPTION_KEY=$(openssl rand -base64 32)

msg_info "Creating Configuration"
cat <<EOF >/Revolt.toml
[database]
mongodb = "mongodb://127.0.0.1:27017"
redis = "redis://127.0.0.1:6379/"

[hosts]
app = "https://${LOCAL_IP}"
api = "https://${LOCAL_IP}/api"
events = "wss://${LOCAL_IP}/ws"
autumn = "https://${LOCAL_IP}/autumn"
january = "https://${LOCAL_IP}/january"

[rabbit]
host = "127.0.0.1"
port = 5672
username = "rabbituser"
password = "${RABBIT_PASS}"

[files]
encryption_key = "${FILES_ENCRYPTION_KEY}"

[files.s3]
endpoint = "http://127.0.0.1:3900"
path_style_buckets = true
region = "garage"
access_key_id = "${GARAGE_ACCESS_KEY}"
secret_access_key = "${GARAGE_SECRET_KEY}"
default_bucket = "revolt-uploads"

[api.registration]
invite_only = false
EOF
ln -sf /Revolt.toml /opt/stoatchat/Revolt.toml
msg_ok "Created Configuration"

msg_info "Configuring Nginx"
# The web client needs a secure context: over plain http navigator.mediaDevices is undefined and it crashes on load
create_self_signed_cert "stoatchat"
cat <<EOF >/etc/nginx/sites-available/stoatchat
server {
    listen 80;
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl;
    ssl_certificate /etc/ssl/stoatchat/stoatchat.crt;
    ssl_certificate_key /etc/ssl/stoatchat/stoatchat.key;

    client_max_body_size 20M;

    location /api {
        proxy_pass http://127.0.0.1:14702/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_redirect / /api/;
    }

    location /ws {
        proxy_pass http://127.0.0.1:14703/;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
    }

    location /autumn {
        proxy_pass http://127.0.0.1:14704/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_redirect / /autumn/;
    }

    location /january {
        proxy_pass http://127.0.0.1:14705/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_redirect / /january/;
    }

    location / {
        root /opt/stoatchat-web/packages/client/dist;
        try_files \$uri \$uri/ /index.html;
    }
}
EOF
ln -sf /etc/nginx/sites-available/stoatchat /etc/nginx/sites-enabled/stoatchat
rm -f /etc/nginx/sites-enabled/default
systemctl enable nginx
$STD nginx -t && systemctl reload nginx
msg_ok "Configured Nginx"

msg_info "Creating Backend Services"
for SVC in api events autumn january crond; do
  case $SVC in
  api)
    PORT=14702
    BIN=revolt-delta
    ;;
  events)
    PORT=14703
    BIN=revolt-bonfire
    ;;
  autumn)
    PORT=14704
    BIN=revolt-autumn
    ;;
  january)
    PORT=14705
    BIN=revolt-january
    ;;
  crond)
    PORT=0
    BIN=revolt-crond
    ;;
  esac
  cat <<EOF >/etc/systemd/system/stoatchat-${SVC}.service
[Unit]
Description=Stoatchat ${SVC} service
After=network.target mongod.service redis-server.service rabbitmq-server.service garage.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/stoatchat
ExecStart=/opt/stoatchat/target/release/${BIN}
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now "stoatchat-${SVC}"
done
msg_ok "Created Backend Services"

motd_ssh
customize
cleanup_lxc
