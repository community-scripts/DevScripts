#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://github.com/causefx/Organizr

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

var_admin_user="${var_admin_user:-admin}"
var_admin_email="${var_admin_email:-admin@example.com}"
var_admin_pass="${var_admin_pass:-$(random_password 16)}"

msg_info "Installing Dependencies"
$STD apt install -y nginx
msg_ok "Installed Dependencies"

PHP_VERSION="8.4" PHP_FPM="YES" PHP_MODULE="ldap" setup_php
fetch_and_deploy_gh_branch "organizr" "causefx/Organizr" "v2-master"

msg_info "Configuring Nginx"
mkdir -p /opt/organizr_data/{data,db}
ln -sfn /opt/organizr_data/data /opt/organizr/data
chown -R www-data:www-data /opt/organizr /opt/organizr_data/data /opt/organizr_data/db
PHP_SOCK=$(get_php_fpm_socket)
cat <<EOF >/etc/nginx/sites-available/organizr
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _;
    root /opt/organizr;
    index index.html index.htm index.php;
    client_max_body_size 0;
    server_tokens off;

    location ~ /\.git {
        deny all;
    }
    location ~ /\.env {
        deny all;
    }
    location ~ /\.ht {
        deny all;
    }

    location / {
        try_files \$uri \$uri/ /index.html /index.php?\$args =404;
    }

    location /api/v2 {
        try_files \$uri /api/v2/index.php\$is_args\$args;
    }

    location ~ \.php\$ {
        fastcgi_split_path_info ^(.+\.php)(/.+)\$;
        fastcgi_pass unix:${PHP_SOCK};
        fastcgi_index index.php;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_buffers 32 32k;
        fastcgi_buffer_size 32k;
    }
}
EOF
nginx_enable_site "organizr"
msg_ok "Configured Nginx"

msg_info "Setting up Organizr"
REG_PASS=$(random_password 16)
$STD curl -fsS -X POST http://127.0.0.1/api/v2/wizard \
  --data-urlencode "license=personal" \
  --data-urlencode "username=${var_admin_user}" \
  --data-urlencode "email=${var_admin_email}" \
  --data-urlencode "password=${var_admin_pass}" \
  --data-urlencode "hashKey=$(random_password 32)" \
  --data-urlencode "registrationPassword=${REG_PASS}" \
  --data-urlencode "api=$(random_password 20)" \
  --data-urlencode "driver=sqlite3" \
  --data-urlencode "dbName=organizr" \
  --data-urlencode "dbPath=/opt/organizr_data/db/"
cat <<EOF >/opt/organizr_data/.env
ORGANIZR_ADMIN_USER=${var_admin_user}
ORGANIZR_ADMIN_EMAIL=${var_admin_email}
ORGANIZR_ADMIN_PASSWORD=${var_admin_pass}
ORGANIZR_REGISTRATION_PASSWORD=${REG_PASS}
EOF
chmod 600 /opt/organizr_data/.env
cat <<EOF >/etc/cron.d/organizr
* * * * * www-data php /opt/organizr/cron.php >/dev/null 2>&1
EOF
systemctl enable -q --now cron
msg_ok "Set up Organizr"

motd_ssh
customize
cleanup_lxc
