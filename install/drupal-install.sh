#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://www.drupal.org/

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

var_admin_user="${var_admin_user:-admin}"
if [[ ! "$var_admin_user" =~ ^[A-Za-z0-9._@-]{2,60}$ ]]; then
  msg_warn "Invalid admin username '${var_admin_user}', using admin"
  var_admin_user="admin"
fi
var_admin_email="${var_admin_email:-admin@example.com}"
if [[ ! "$var_admin_email" =~ ^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$ ]]; then
  msg_warn "Invalid admin email '${var_admin_email}', using admin@example.com"
  var_admin_email="admin@example.com"
fi
var_admin_pass="${var_admin_pass:-$(random_password)}"

msg_info "Installing Dependencies"
$STD apt install -y nginx
msg_ok "Installed Dependencies"

setup_mariadb
MARIADB_DB_NAME="drupal" MARIADB_DB_USER="drupal" MARIADB_DB_CREDS_FILE="/dev/null" setup_mariadb_db
PHP_VERSION="8.4" PHP_FPM="YES" setup_php
setup_composer

msg_info "Installing Drupal"
$STD composer create-project --no-interaction --no-install "drupal/recommended-project:${var_appversion:-^11}" /opt/drupal
cd /opt/drupal
$STD composer update --no-interaction --with "drupal/core-recommended:${var_appversion:-^11}"
$STD composer require --no-interaction drush/drush
mkdir -p /opt/drupal_data/private /opt/drupal_data/config/sync
cp web/sites/default/default.settings.php web/sites/default/settings.php
cat <<'EOF' >>web/sites/default/settings.php
$settings['config_sync_directory'] = '/opt/drupal_data/config/sync';
$settings['file_private_path'] = '/opt/drupal_data/private';
EOF
$STD vendor/bin/drush site:install standard --yes \
  --db-url="mysql://${MARIADB_DB_USER}:${MARIADB_DB_PASS}@localhost/${MARIADB_DB_NAME}" \
  --site-name="Drupal" \
  --site-mail="$var_admin_email" \
  --account-name="$var_admin_user" \
  --account-pass="$var_admin_pass" \
  --account-mail="$var_admin_email"
$STD vendor/bin/drush recipe -y /opt/drupal/web/core/recipes/page_content_type
$STD vendor/bin/drush recipe -y /opt/drupal/web/core/recipes/article_tags
chown -R www-data:www-data web/sites/default/files /opt/drupal_data/private
jq -r '.packages[] | select(.name == "drupal/core") | .version' composer.lock >~/.drupal
cat <<EOF >/opt/drupal_data/.env
DRUPAL_ADMIN_USER=${var_admin_user}
DRUPAL_ADMIN_PASS=${var_admin_pass}
DRUPAL_ADMIN_EMAIL=${var_admin_email}
DRUPAL_DB_NAME=${MARIADB_DB_NAME}
DRUPAL_DB_USER=${MARIADB_DB_USER}
DRUPAL_DB_PASS=${MARIADB_DB_PASS}
EOF
chmod 600 /opt/drupal_data/.env
msg_ok "Installed Drupal"

msg_info "Configuring Nginx"
PHP_SOCK=$(get_php_fpm_socket)
cat <<EOF >/etc/nginx/sites-available/drupal
server {
    listen 80;
    listen [::]:80;
    server_name _;

    root /opt/drupal/web;
    index index.php;

    client_max_body_size 128M;
    server_tokens off;
    fastcgi_hide_header X-Powered-By;

    location = /favicon.ico {
        log_not_found off;
        access_log off;
    }
    location = /robots.txt {
        allow all;
        log_not_found off;
        access_log off;
    }
    location ~* \.(txt|log)\$ {
        deny all;
    }
    location ~ \..*/.*\.php\$ {
        return 403;
    }
    location ~ ^/sites/.*/private/ {
        return 403;
    }
    location ~ ^/sites/[^/]+/files/.*\.php\$ {
        deny all;
    }
    location ~* ^/.well-known/ {
        allow all;
    }
    location ~ (^|/)\. {
        return 403;
    }
    location / {
        try_files \$uri /index.php?\$query_string;
    }
    location @rewrite {
        rewrite ^ /index.php;
    }
    location ~ /vendor/.*\.php\$ {
        deny all;
        return 404;
    }
    location ~* \.(engine|inc|install|make|module|profile|po|sh|.*sql|theme|twig|tpl(\.php)?|xtmpl|yml)(~|\.sw[op]|\.bak|\.orig|\.save)?\$ {
        deny all;
        return 404;
    }
    location ~ '\.php\$|^/update.php' {
        fastcgi_split_path_info ^(.+?\.php)(|/.*)\$;
        try_files \$fastcgi_script_name =404;
        include fastcgi_params;
        fastcgi_param HTTP_PROXY "";
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_param PATH_INFO \$fastcgi_path_info;
        fastcgi_param QUERY_STRING \$query_string;
        fastcgi_intercept_errors on;
        fastcgi_pass unix:${PHP_SOCK};
    }
    location ~ ^/sites/.*/files/styles/ {
        try_files \$uri @rewrite;
    }
    location ~ ^(/[a-z\-]+)?/system/files/ {
        try_files \$uri /index.php?\$query_string;
    }
    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|webp|woff2?)\$ {
        try_files \$uri @rewrite;
        expires max;
        log_not_found off;
    }
}
EOF
nginx_enable_site "drupal"
msg_ok "Configured Nginx"

motd_ssh
customize
cleanup_lxc
