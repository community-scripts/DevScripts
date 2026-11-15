#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://github.com/HiEventsDev/hi.events

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

var_mail_from="${var_mail_from:-noreply@example.com}"
var_smtp_port="${var_smtp_port:-587}"

msg_info "Installing Dependencies"
$STD apt install -y \
  nginx \
  redis-server
msg_ok "Installed Dependencies"

PG_VERSION="17" setup_postgresql
PG_DB_NAME="hievents" PG_DB_USER="hievents" PG_DB_EXTENSIONS="pg_trgm" PG_DB_CREDS_FILE="/dev/null" setup_postgresql_db
PHP_VERSION="8.4" PHP_FPM="YES" setup_php
setup_composer
NODE_VERSION="22" NODE_MODULE="yarn@1" setup_nodejs
fetch_and_deploy_gh_release "hi-events" "HiEventsDev/hi.events" "tarball"

msg_info "Configuring Hi.Events"
mkdir -p /opt/hi-events_data
mv /opt/hi-events/backend/storage /opt/hi-events_data/storage
ln -s /opt/hi-events_data/storage /opt/hi-events/backend/storage
cat <<EOF >/opt/hi-events_data/.env
APP_NAME=Hi.Events
APP_ENV=production
APP_DEBUG=false
APP_KEY=
APP_URL=https://${LOCAL_IP}/api
APP_FRONTEND_URL=https://${LOCAL_IP}
APP_CDN_URL=https://${LOCAL_IP}/storage
APP_DISABLE_REGISTRATION=false
APP_SAAS_MODE_ENABLED=false
APP_TRUSTED_PROXIES=*
APP_PLATFORM_SUPPORT_EMAIL=${var_mail_from}

DB_CONNECTION=pgsql
DB_HOST=127.0.0.1
DB_PORT=5432
DB_DATABASE=hievents
DB_USERNAME=hievents
DB_PASSWORD=${PG_DB_PASS}

CACHE_DRIVER=file
SESSION_DRIVER=file
QUEUE_CONNECTION=redis
WEBHOOK_QUEUE_NAME=webhook-queue
REDIS_HOST=127.0.0.1
REDIS_PORT=6379
REDIS_PASSWORD=null

LOG_CHANNEL=daily

FILESYSTEM_PUBLIC_DISK=public
FILESYSTEM_PRIVATE_DISK=local

MAIL_MAILER=$([[ -n "${var_smtp_host:-}" ]] && echo smtp || echo log)
MAIL_HOST=${var_smtp_host:-}
MAIL_PORT=${var_smtp_port}
MAIL_USERNAME=${var_smtp_user:-}
MAIL_PASSWORD=${var_smtp_pass:-}
MAIL_FROM_ADDRESS=${var_mail_from}
MAIL_FROM_NAME=Hi.Events

STRIPE_PUBLIC_KEY=
STRIPE_SECRET_KEY=
STRIPE_WEBHOOK_SECRET=

JWT_SECRET=
JWT_ALGO=HS256
EOF
cat <<EOF >/opt/hi-events_data/frontend.env
NODE_ENV=production
NODE_PORT=5678
VITE_FRONTEND_URL=https://${LOCAL_IP}
VITE_API_URL_CLIENT=https://${LOCAL_IP}/api
VITE_API_URL_SERVER=http://127.0.0.1:8080/api
VITE_STRIPE_PUBLISHABLE_KEY=
VITE_APP_NAME=Hi.Events
EOF
chmod 600 /opt/hi-events_data/.env /opt/hi-events_data/frontend.env
ln -sf /opt/hi-events_data/.env /opt/hi-events/backend/.env
msg_ok "Configured Hi.Events"

msg_info "Building Hi.Events Backend"
cd /opt/hi-events/backend
$STD composer install --no-dev --no-interaction --prefer-dist --optimize-autoloader
$STD php artisan key:generate --force
$STD php artisan jwt:secret --force
$STD php artisan migrate --force
$STD php artisan storage:link
chown -R www-data:www-data /opt/hi-events/backend /opt/hi-events_data/storage /opt/hi-events_data/.env
msg_ok "Built Hi.Events Backend"

msg_info "Building Hi.Events Frontend"
cd /opt/hi-events/frontend
$STD yarn install --frozen-lockfile --network-timeout 600000
$STD yarn build
$STD yarn cache clean
msg_ok "Built Hi.Events Frontend"

msg_info "Configuring Nginx"
create_self_signed_cert "hi-events"
PHP_SOCK=$(get_php_fpm_socket)
cat <<EOF >/etc/nginx/sites-available/hi-events
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _;
    return 301 https://\$host\$request_uri;
}

server {
    listen 127.0.0.1:8080;
    root /opt/hi-events/backend/public;

    location ^~ /api/ {
        rewrite ^/api(/.*)\$ /index.php\$1 break;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_param REQUEST_URI \$1;
        fastcgi_param HTTP_X_FORWARDED_PREFIX /api;
        fastcgi_pass unix:${PHP_SOCK};
    }
}

server {
    listen 443 ssl default_server;
    listen [::]:443 ssl default_server;
    server_name _;

    ssl_certificate /etc/ssl/hi-events/hi-events.crt;
    ssl_certificate_key /etc/ssl/hi-events/hi-events.key;

    root /opt/hi-events/backend/public;
    index index.php;
    charset utf-8;
    client_max_body_size 20M;

    location /storage {
        alias /opt/hi-events_data/storage/app/public;
        access_log off;
        expires max;
        add_header Cache-Control "public";
    }

    location ~ ^/\.well-known/(oauth-authorization-server|oauth-protected-resource|openid-configuration) {
        rewrite ^(/.*)\$ /index.php\$1 break;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_param REQUEST_URI \$1;
        fastcgi_param HTTP_X_FORWARDED_PREFIX /api;
        fastcgi_pass unix:${PHP_SOCK};
    }

    location ^~ /api/ {
        rewrite ^/api(/.*)\$ /index.php\$1 break;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_param REQUEST_URI \$1;
        fastcgi_param HTTP_X_FORWARDED_PREFIX /api;
        fastcgi_pass unix:${PHP_SOCK};
    }

    location / {
        proxy_pass http://127.0.0.1:5678;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    location ~ /\.(?!well-known).* {
        deny all;
    }
}
EOF
nginx_enable_site "hi-events"
msg_ok "Configured Nginx"

msg_info "Creating Services"
cat <<EOF >/etc/systemd/system/hi-events-frontend.service
[Unit]
Description=Hi.Events Frontend
After=network.target

[Service]
Type=simple
WorkingDirectory=/opt/hi-events/frontend
EnvironmentFile=/opt/hi-events_data/frontend.env
ExecStart=/usr/bin/node --import ./instrument.mjs server.js
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
cat <<EOF >/etc/systemd/system/hi-events-queue.service
[Unit]
Description=Hi.Events Queue Worker
After=network.target postgresql.service redis-server.service

[Service]
Type=simple
User=www-data
WorkingDirectory=/opt/hi-events/backend
ExecStart=/usr/bin/php artisan queue:work --queue=default,webhook-queue,occurrences --sleep=3 --tries=3 --timeout=60
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
cat <<EOF >/etc/systemd/system/hi-events-scheduler.service
[Unit]
Description=Hi.Events Scheduler
After=network.target postgresql.service redis-server.service

[Service]
Type=simple
User=www-data
WorkingDirectory=/opt/hi-events/backend
ExecStart=/usr/bin/php artisan schedule:work
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now redis-server hi-events-frontend hi-events-queue hi-events-scheduler
msg_ok "Created Services"

motd_ssh
customize
cleanup_lxc
