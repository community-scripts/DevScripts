#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: untect
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://github.com/madeofpendletonwool/PinePods

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
  pkg-config \
  libssl-dev \
  libmariadb-dev \
  nginx \
  valkey-server
msg_ok "Installed Dependencies"

PG_VERSION="18" setup_postgresql
PG_DB_NAME="pinepods_database" PG_DB_USER="pinepods" setup_postgresql_db
PYTHON_VERSION="3.11" setup_uv
setup_go
RUST_PROFILE="minimal" setup_rust
setup_ffmpeg
fetch_and_deploy_gh_release "trunk" "trunk-rs/trunk" "prebuild" "latest" "/usr/local/bin" "trunk-$(arch_resolve "x86_64" "aarch64")-unknown-linux-gnu.tar.gz"
fetch_and_deploy_gh_release "yt-dlp" "yt-dlp/yt-dlp" "singlefile" "latest" "/usr/local/bin" "$(arch_resolve "yt-dlp_linux" "yt-dlp_linux_aarch64")"
fetch_and_deploy_gh_release "pinepods" "madeofpendletonwool/PinePods" "tarball"

msg_info "Building PinePods"
$STD rustup target add wasm32-unknown-unknown
cd /opt/pinepods/web
RUSTFLAGS="--cfg=web_sys_unstable_apis --cfg getrandom_backend=\"wasm_js\"" $STD trunk build --features server_build --release
rm -rf /var/www/html
cp -r /opt/pinepods/web/dist /var/www/html
cp -r /opt/pinepods/web/src/translations /var/www/html/static/translations
cd /opt/pinepods/gpodder-api
CGO_ENABLED=0 $STD go build -ldflags="-s -w" -o /usr/local/bin/gpodder-api ./cmd/server/
cd /opt/pinepods/rust-api
$STD cargo build --release
cp target/release/pinepods-api /usr/local/bin/pinepods-api
cd /opt/pinepods
$STD uv venv --python 3.11 /opt/pinepods/.venv
$STD uv pip install -p /opt/pinepods/.venv/bin/python -r requirements.txt
rm -rf /opt/pinepods/web/target /opt/pinepods/web/dist /opt/pinepods/rust-api/target
$STD go clean -cache -modcache
msg_ok "Built PinePods"

msg_info "Configuring PinePods"
# The API hardcodes these paths, as well as /pinepods/current_version
mkdir -p /opt/pinepods/{downloads,backups,local-media} /opt/pinepods_data /pinepods
cp ~/.pinepods /pinepods/current_version
cat <<EOF >/opt/pinepods_data/.env
DB_TYPE=postgresql
DB_HOST=127.0.0.1
DB_PORT=5432
DB_USER=${PG_DB_USER}
DB_PASSWORD=${PG_DB_PASS}
DB_NAME=${PG_DB_NAME}
VALKEY_HOST=127.0.0.1
VALKEY_PORT=6379
SEARCH_API_URL=https://search.pinepods.online/api/search
PEOPLE_API_URL=https://people.pinepods.online
HOSTNAME=http://${LOCAL_IP}:8040
SERVER_URL=http://${LOCAL_IP}:8040
DEFAULT_LANGUAGE=en
DEBUG_MODE=false
EOF
chmod 600 /opt/pinepods_data/.env
msg_ok "Configured PinePods"

msg_info "Configuring Nginx"
cat <<'EOF' >/etc/nginx/sites-available/pinepods
server {
    listen 8040;
    server_name _;
    client_max_body_size 0;

    root /var/www/html;
    index index.html;

    add_header 'Access-Control-Allow-Origin' '*' always;
    add_header 'Access-Control-Allow-Methods' 'GET, POST, OPTIONS, DELETE, PUT' always;
    add_header 'Access-Control-Allow-Headers' 'DNT,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range,Api-Key,Authorization' always;
    add_header 'Access-Control-Expose-Headers' 'Content-Length,Content-Range' always;

    location /rss/ {
        rewrite ^/rss/(\d+)(?:/(\d+))?$ /api/feed/$1$2 last;
        proxy_pass http://127.0.0.1:8032;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header Api-Key $arg_api_key;
        add_header Content-Type "application/rss+xml; charset=utf-8";
        expires 1h;
        add_header Cache-Control "public, no-transform";
    }

    location / {
        if ($request_method = 'OPTIONS') {
            add_header 'Access-Control-Max-Age' 1728000;
            add_header 'Content-Type' 'text/plain; charset=utf-8';
            add_header 'Content-Length' 0;
            return 204;
        }
        try_files $uri $uri/ /index.html;
    }

    location /api {
        add_header 'Access-Control-Allow-Origin' '*' always;
        add_header 'Access-Control-Allow-Methods' 'GET, POST, OPTIONS, DELETE, PUT' always;
        add_header 'Access-Control-Allow-Headers' 'DNT,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range,Api-Key,Authorization' always;
        add_header 'Access-Control-Expose-Headers' 'Content-Length,Content-Range' always;

        proxy_pass http://127.0.0.1:8032;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        if ($request_method = 'OPTIONS') {
            add_header 'Access-Control-Allow-Origin' '*' always;
            add_header 'Access-Control-Allow-Methods' 'GET, POST, OPTIONS, DELETE, PUT' always;
            add_header 'Access-Control-Allow-Headers' 'DNT,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range,Api-Key,Authorization' always;
            add_header 'Access-Control-Max-Age' 1728000;
            add_header 'Content-Type' 'text/plain; charset=utf-8';
            add_header 'Content-Length' 0;
            return 204;
        }
    }

    location ~ ^/(api/2|auth|subscriptions|devices|updates|episodes|settings|lists|favorites|sync-devices|search|suggestions|toplist|tag|tags|data)/ {
        proxy_pass http://127.0.0.1:8042;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        add_header 'Access-Control-Allow-Origin' '*' always;
        add_header 'Access-Control-Allow-Methods' 'GET, POST, OPTIONS, DELETE, PUT' always;
        add_header 'Access-Control-Allow-Headers' 'DNT,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range,Api-Key,Authorization' always;

        if ($request_method = 'OPTIONS') {
            add_header 'Access-Control-Allow-Origin' '*' always;
            add_header 'Access-Control-Allow-Methods' 'GET, POST, OPTIONS, DELETE, PUT' always;
            add_header 'Access-Control-Allow-Headers' 'DNT,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range,Api-Key,Authorization' always;
            add_header 'Access-Control-Max-Age' 1728000;
            add_header 'Content-Type' 'text/plain; charset=utf-8';
            add_header 'Content-Length' 0;
            return 204;
        }

        proxy_read_timeout 300;
        proxy_send_timeout 300;
    }

    location /api/gpodder {
        add_header 'Access-Control-Allow-Origin' '*' always;
        add_header 'Access-Control-Allow-Methods' 'GET, POST, OPTIONS, DELETE, PUT' always;
        add_header 'Access-Control-Allow-Headers' 'DNT,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range,Api-Key,Authorization' always;
        add_header 'Access-Control-Expose-Headers' 'Content-Length,Content-Range' always;

        proxy_pass http://127.0.0.1:8032;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 1800;
        proxy_send_timeout 1800;

        if ($request_method = 'OPTIONS') {
            add_header 'Access-Control-Allow-Origin' '*' always;
            add_header 'Access-Control-Allow-Methods' 'GET, POST, OPTIONS, DELETE, PUT' always;
            add_header 'Access-Control-Allow-Headers' 'DNT,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range,Api-Key,Authorization' always;
            add_header 'Access-Control-Max-Age' 1728000;
            add_header 'Content-Type' 'text/plain; charset=utf-8';
            add_header 'Content-Length' 0;
            return 204;
        }
    }

    location ~ ^/ws/api/(data|tasks)/ {
        proxy_pass http://127.0.0.1:8032;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "Upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 86400;
        proxy_send_timeout 86400;
    }

    location ~* \.wasm$ {
        types {
            application/wasm wasm;
        }
    }
}
EOF
nginx_enable_site "pinepods"
msg_ok "Configured Nginx"

msg_info "Creating Services"
cat <<EOF >/etc/systemd/system/pinepods-api.service
[Unit]
Description=PinePods API
After=network.target postgresql.service valkey-server.service
Requires=postgresql.service valkey-server.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/pinepods
EnvironmentFile=/opt/pinepods_data/.env
ExecStartPre=/opt/pinepods/.venv/bin/python /opt/pinepods/startup/setup_database_new.py
ExecStart=/usr/local/bin/pinepods-api
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
cat <<EOF >/etc/systemd/system/pinepods-gpodder.service
[Unit]
Description=PinePods gPodder API
After=pinepods-api.service
Requires=pinepods-api.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/pinepods
EnvironmentFile=/opt/pinepods_data/.env
Environment=SERVER_PORT=8042
ExecStart=/usr/local/bin/gpodder-api
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now pinepods-api pinepods-gpodder
msg_ok "Created Services"

motd_ssh
customize
cleanup_lxc
