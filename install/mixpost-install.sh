#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://github.com/inovector/mixpost

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

var_admin_email="${var_admin_email:-admin@example.com}"
var_admin_pass="${var_admin_pass:-$(random_password 16)}"

msg_info "Installing Dependencies"
$STD apt install -y \
  nginx \
  redis-server \
  unzip
msg_ok "Installed Dependencies"

setup_ffmpeg
setup_mariadb
MARIADB_DB_NAME="mixpost" MARIADB_DB_USER="mixpost" MARIADB_DB_CREDS_FILE="/dev/null" setup_mariadb_db
PHP_VERSION="8.4" PHP_FPM="YES" setup_php
setup_composer

MIXPOST_VERSION="${var_appversion:-$(get_latest_github_release "inovector/mixpost")}"
msg_info "Installing Mixpost"
$STD composer create-project --no-dev --no-interaction inovector/mixpostapp /opt/mixpost
cd /opt/mixpost
$STD composer require "inovector/mixpost:${MIXPOST_VERSION#v}" --update-no-dev --update-with-all-dependencies --no-interaction
cat <<EOF >~/.mixpost
${MIXPOST_VERSION#v}
EOF
msg_ok "Installed Mixpost"

msg_info "Configuring Mixpost"
mkdir -p /opt/mixpost_data
mv /opt/mixpost/storage /opt/mixpost_data/storage
ln -s /opt/mixpost_data/storage /opt/mixpost/storage
cat <<EOF >/opt/mixpost_data/.env
APP_NAME=Mixpost
APP_KEY=
APP_DEBUG=false
APP_URL=http://${LOCAL_IP}
DB_HOST=127.0.0.1
DB_PORT=3306
DB_DATABASE=mixpost
DB_USERNAME=mixpost
DB_PASSWORD=${MARIADB_DB_PASS}
REDIS_HOST=127.0.0.1
REDIS_PASSWORD=null
REDIS_PORT=6379
MIXPOST_DISK=public
MAIL_MAILER=log
ADMIN_EMAIL=${var_admin_email}
ADMIN_PASSWORD=${var_admin_pass}
EOF
chmod 600 /opt/mixpost_data/.env
ln -sf /opt/mixpost_data/.env /opt/mixpost/.env
$STD php artisan key:generate --force
$STD php artisan migrate --force
SHELL_INTERACTIVE=1 $STD php artisan mixpost-auth:create <<EOF
Admin
${var_admin_email}
${var_admin_pass}
EOF
$STD php artisan optimize
chown -R www-data:www-data /opt/mixpost /opt/mixpost_data
msg_ok "Configured Mixpost"

msg_info "Configuring Nginx"
PHP_SOCK=$(get_php_fpm_socket)
cat <<EOF >/etc/nginx/sites-available/mixpost
server {
    listen 80;
    listen [::]:80;
    server_name _;

    root /opt/mixpost/public;
    index index.php;
    client_max_body_size 128M;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }
    location ~ \.php\$ {
        fastcgi_pass unix:${PHP_SOCK};
        fastcgi_param SCRIPT_FILENAME \$realpath_root\$fastcgi_script_name;
        include fastcgi_params;
    }
    location ~ /\.(?!well-known).* {
        deny all;
    }
}
EOF
nginx_enable_site "mixpost"
msg_ok "Configured Nginx"

msg_info "Creating Services"
cat <<EOF >/etc/systemd/system/mixpost-horizon.service
[Unit]
Description=Mixpost Horizon
After=network.target mariadb.service redis-server.service
Requires=redis-server.service

[Service]
Type=simple
User=www-data
WorkingDirectory=/opt/mixpost
ExecStart=/usr/bin/php /opt/mixpost/artisan horizon
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
cat <<EOF >/etc/systemd/system/mixpost-scheduler.service
[Unit]
Description=Mixpost Scheduler
After=network.target mariadb.service redis-server.service

[Service]
Type=simple
User=www-data
WorkingDirectory=/opt/mixpost
ExecStart=/usr/bin/php /opt/mixpost/artisan schedule:work
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now redis-server mixpost-horizon mixpost-scheduler
msg_ok "Created Services"

motd_ssh
customize
cleanup_lxc
