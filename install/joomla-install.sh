#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://github.com/joomla/joomla-cms

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

var_admin_user="${var_admin_user:-admin}"
if [[ ! "$var_admin_user" =~ ^[A-Za-z0-9._@-]{2,150}$ ]]; then
  msg_warn "Invalid admin username '${var_admin_user}', using admin"
  var_admin_user="admin"
fi
var_admin_email="${var_admin_email:-admin@example.com}"
if [[ ! "$var_admin_email" =~ ^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$ ]]; then
  msg_warn "Invalid admin email '${var_admin_email}', using admin@example.com"
  var_admin_email="admin@example.com"
fi
var_admin_pass="${var_admin_pass:-$(random_password)}"
if ((${#var_admin_pass} < 12)); then
  msg_warn "Joomla needs an admin password of at least 12 characters, generating one"
  var_admin_pass="$(random_password)"
fi

msg_info "Installing Dependencies"
$STD apt install -y nginx
msg_ok "Installed Dependencies"

setup_mariadb
MARIADB_DB_NAME="joomla" MARIADB_DB_USER="joomla" MARIADB_DB_CREDS_FILE="/dev/null" setup_mariadb_db
PHP_VERSION="8.4" PHP_FPM="YES" setup_php
fetch_and_deploy_gh_release "joomla" "joomla/joomla-cms" "prebuild" "latest" "/opt/joomla" "Joomla_*-Stable-Full_Package.tar.gz"

msg_info "Installing Joomla"
cd /opt/joomla
$STD php installation/joomla.php install --no-interaction \
  --site-name="Joomla" \
  --admin-user="Administrator" \
  --admin-username="$var_admin_user" \
  --admin-password="$var_admin_pass" \
  --admin-email="$var_admin_email" \
  --db-type="mysqli" \
  --db-host="localhost" \
  --db-user="$MARIADB_DB_USER" \
  --db-pass="$MARIADB_DB_PASS" \
  --db-name="$MARIADB_DB_NAME"
$STD php cli/joomla.php config:set sef_rewrite=true
chown -R www-data:www-data /opt/joomla
mkdir -p /opt/joomla_data
cat <<EOF >/opt/joomla_data/.env
JOOMLA_ADMIN_USER=${var_admin_user}
JOOMLA_ADMIN_PASS=${var_admin_pass}
JOOMLA_ADMIN_EMAIL=${var_admin_email}
JOOMLA_DB_NAME=${MARIADB_DB_NAME}
JOOMLA_DB_USER=${MARIADB_DB_USER}
JOOMLA_DB_PASS=${MARIADB_DB_PASS}
EOF
chmod 600 /opt/joomla_data/.env
msg_ok "Installed Joomla"

msg_info "Configuring Nginx"
PHP_SOCK=$(get_php_fpm_socket)
cat <<EOF >/etc/nginx/sites-available/joomla
server {
    listen 80;
    listen [::]:80;
    server_name _;

    root /opt/joomla;
    index index.php index.html;

    client_max_body_size 128M;
    server_tokens off;
    fastcgi_hide_header X-Powered-By;
    add_header X-Content-Type-Options nosniff;

    location ~ ^/(administrator/)?(logs|cache|tmp)/ {
        deny all;
    }
    location ~ ^/(cli/|configuration\.php|htaccess\.txt|web\.config\.txt|README\.txt|LICENSE\.txt) {
        deny all;
    }
    location ~ /\. {
        deny all;
    }
    location ~* /(images|media)/.*\.(php|pl|py|jsp|asp|sh|cgi)\$ {
        deny all;
    }
    location /api/ {
        try_files \$uri \$uri/ /api/index.php?\$args;
    }
    location / {
        try_files \$uri \$uri/ /index.php?\$args;
    }
    location ~ \.php\$ {
        try_files \$uri =404;
        fastcgi_pass unix:${PHP_SOCK};
        fastcgi_index index.php;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
    }
    location ~* \.(ico|pdf)\$ {
        expires 1y;
    }
    location ~* \.(js|css|png|jpg|jpeg|gif|svg|webp|woff2?)\$ {
        expires 14d;
    }
}
EOF
nginx_enable_site "joomla"
msg_ok "Configured Nginx"

motd_ssh
customize
cleanup_lxc
