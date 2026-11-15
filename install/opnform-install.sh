#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://github.com/OpnForm/OpnForm

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt install -y \
  nginx \
  redis-server
msg_ok "Installed Dependencies"

PG_VERSION="17" setup_postgresql
PG_DB_NAME="opnform" PG_DB_USER="opnform" PG_DB_CREDS_FILE="/dev/null" setup_postgresql_db
PHP_VERSION="8.3" PHP_FPM="YES" PHP_MEMORY_LIMIT="1G" PHP_UPLOAD_MAX_FILESIZE="64M" PHP_POST_MAX_SIZE="64M" PHP_MAX_EXECUTION_TIME="600" setup_php
setup_composer
NODE_VERSION="24" setup_nodejs
fetch_and_deploy_gh_release "opnform" "OpnForm/OpnForm" "tarball"

msg_info "Configuring OpnForm"
FRONT_API_SECRET=$(random_password 40)
mkdir -p /opt/opnform_data
mv /opt/opnform/api/storage /opt/opnform_data/storage
ln -s /opt/opnform_data/storage /opt/opnform/api/storage
cat <<EOF >/opt/opnform_data/api.env
APP_NAME="OpnForm"
APP_ENV=production
APP_KEY=
APP_DEBUG=false
APP_URL=http://${LOCAL_IP}
FRONT_URL=http://${LOCAL_IP}
FRONT_API_SECRET=${FRONT_API_SECRET}

LOG_CHANNEL=daily
LOG_LEVEL=warning

DB_CONNECTION=pgsql
DB_HOST=127.0.0.1
DB_PORT=5432
DB_DATABASE=opnform
DB_USERNAME=opnform
DB_PASSWORD=${PG_DB_PASS}

REDIS_HOST=127.0.0.1
REDIS_PORT=6379
CACHE_DRIVER=redis
QUEUE_CONNECTION=redis
SESSION_DRIVER=redis

FILESYSTEM_DRIVER=local
LOCAL_FILESYSTEM_VISIBILITY=public

MAIL_MAILER=log
MAIL_HOST=
MAIL_PORT=
MAIL_USERNAME=
MAIL_PASSWORD=
MAIL_ENCRYPTION=
MAIL_FROM_ADDRESS=forms@example.com
MAIL_FROM_NAME=OpnForm

JWT_TTL=1440
JWT_SECRET=$(random_password 40)
JWT_SKIP_IP_UA_VALIDATION=false
PUBLIC_UPLOADS_RATE_LIMIT_PER_MINUTE=30
PUBLIC_UPLOADS_RATE_LIMIT_PER_HOUR=300

TRUSTED_PROXIES=
SHOW_OFFICIAL_TEMPLATES=true
EOF
cat <<EOF >/opt/opnform_data/client.env
NODE_ENV=production
NITRO_HOST=127.0.0.1
NITRO_PORT=3000
NUXT_PUBLIC_APP_URL=/
NUXT_PUBLIC_API_BASE=/api
NUXT_PRIVATE_API_BASE=http://127.0.0.1/api
NUXT_PUBLIC_ENV=dev
NUXT_API_SECRET=${FRONT_API_SECRET}
NUXT_PUBLIC_H_CAPTCHA_SITE_KEY=
NUXT_PUBLIC_RE_CAPTCHA_SITE_KEY=
NUXT_PUBLIC_ROOT_REDIRECT_URL=
EOF
chmod 600 /opt/opnform_data/api.env /opt/opnform_data/client.env
ln -sf /opt/opnform_data/api.env /opt/opnform/api/.env
msg_ok "Configured OpnForm"

msg_info "Building OpnForm API"
cd /opt/opnform/api
$STD composer install --no-dev --no-interaction --prefer-dist --optimize-autoloader
$STD php artisan key:generate --force
$STD php artisan storage:link
$STD php artisan migrate --force
$STD php artisan passport:keys --force
$STD php artisan telemetry:initialize-instance
$STD php artisan optimize
chown -R www-data:www-data /opt/opnform/api /opt/opnform_data/storage /opt/opnform_data/api.env
chmod 600 /opt/opnform_data/storage/oauth-private.key
msg_ok "Built OpnForm API"

msg_info "Building OpnForm Client"
cd /opt/opnform/client
export NODE_OPTIONS="--max-old-space-size=4096" NUXT_TELEMETRY_DISABLED=1
$STD npm ci
$STD npm run build
rm -rf /opt/opnform/client/node_modules
msg_ok "Built OpnForm Client"

msg_info "Configuring Nginx"
PHP_SOCK=$(get_php_fpm_socket)
cat <<EOF >/etc/nginx/sites-available/opnform
map \$request_uri \$opnform_api_uri {
    ~^/api(/.*\$) \$1;
    default \$request_uri;
}

server {
    listen 80;
    listen [::]:80;
    server_name _;
    root /opt/opnform/api/public;
    index index.html index.htm index.php;
    client_max_body_size 64m;

    location / {
        proxy_http_version 1.1;
        proxy_pass http://127.0.0.1:3000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-Host \$host;
        proxy_set_header X-Forwarded-Port \$server_port;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "Upgrade";
    }

    location ^~ /api/_nuxt_icon/ {
        proxy_http_version 1.1;
        proxy_pass http://127.0.0.1:3000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-Host \$host;
        proxy_set_header X-Forwarded-Port \$server_port;
    }

    location ~/(api|open|local\/temp|forms\/assets)/ {
        try_files \$uri \$uri/ /index.php\$is_args\$args;
    }

    location ~ \.php\$ {
        fastcgi_split_path_info ^(.+\.php)(/.+)\$;
        fastcgi_pass unix:${PHP_SOCK};
        fastcgi_index index.php;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME \$document_root/index.php;
        fastcgi_param REQUEST_URI \$opnform_api_uri;
    }

    location ~ /\. {
        deny all;
    }
}
EOF
nginx_enable_site "opnform"
msg_ok "Configured Nginx"

msg_info "Creating Services"
cat <<EOF >/etc/systemd/system/opnform-client.service
[Unit]
Description=OpnForm Client
After=network.target

[Service]
Type=simple
WorkingDirectory=/opt/opnform/client
EnvironmentFile=/opt/opnform_data/client.env
ExecStart=/usr/bin/node .output/server/index.mjs
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
cat <<EOF >/etc/systemd/system/opnform-worker.service
[Unit]
Description=OpnForm Queue Worker
After=network.target postgresql.service redis-server.service

[Service]
Type=simple
User=www-data
WorkingDirectory=/opt/opnform/api
ExecStart=/usr/bin/php artisan queue:work
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
cat <<EOF >/etc/systemd/system/opnform-scheduler.service
[Unit]
Description=OpnForm Scheduler
After=network.target postgresql.service redis-server.service

[Service]
Type=simple
User=www-data
WorkingDirectory=/opt/opnform/api
ExecStart=/usr/bin/php artisan schedule:work
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now redis-server opnform-client opnform-worker opnform-scheduler
msg_ok "Created Services"

motd_ssh
customize
cleanup_lxc
