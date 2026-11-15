#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://github.com/alextselegidis/easyappointments

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

var_admin_user="${var_admin_user:-admin}"
if [[ ! "$var_admin_user" =~ ^[a-zA-Z0-9_@.-]{3,50}$ ]]; then
  msg_warn "Invalid admin username '${var_admin_user}', using admin"
  var_admin_user="admin"
fi
var_admin_email="${var_admin_email:-admin@example.com}"
if [[ ! "$var_admin_email" =~ ^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$ ]]; then
  msg_warn "Invalid admin email '${var_admin_email}', using admin@example.com"
  var_admin_email="admin@example.com"
fi
var_admin_pass="${var_admin_pass:-$(random_password 16)}"
if ((${#var_admin_pass} < 8)); then
  msg_warn "Admin password is shorter than 8 characters, generating one"
  var_admin_pass="$(random_password 16)"
fi

msg_info "Installing Dependencies"
$STD apt install -y nginx
msg_ok "Installed Dependencies"

setup_mariadb
MARIADB_DB_NAME="easyappointments" MARIADB_DB_USER="easyappointments" setup_mariadb_db
PHP_VERSION="8.4" PHP_FPM="YES" PHP_MODULE="ldap" setup_php
fetch_and_deploy_gh_release "easyappointments" "alextselegidis/easyappointments" "prebuild" "latest" "/opt/easyappointments" "easyappointments-*.zip"

msg_info "Configuring Easy!Appointments"
cd /opt/easyappointments
cp config-sample.php config.php
sed -i \
  -e "s|const BASE_URL = .*|const BASE_URL = 'http://${LOCAL_IP}';|" \
  -e "s|const DB_HOST = .*|const DB_HOST = 'localhost';|" \
  -e "s|const DB_NAME = .*|const DB_NAME = '${MARIADB_DB_NAME}';|" \
  -e "s|const DB_USERNAME = .*|const DB_USERNAME = '${MARIADB_DB_USER}';|" \
  -e "s|const DB_PASSWORD = .*|const DB_PASSWORD = '${MARIADB_DB_PASS}';|" \
  config.php
chown -R www-data:www-data /opt/easyappointments
msg_ok "Configured Easy!Appointments"

msg_info "Configuring Nginx"
PHP_SOCK=$(get_php_fpm_socket)
cat <<EOF >/etc/nginx/sites-available/easyappointments
server {
    listen 80;
    server_name _;

    root /opt/easyappointments;
    index index.php;

    client_max_body_size 128M;

    location / {
        try_files \$uri \$uri/ /index.php?\$args;
    }

    location ~ ^/(application|system|storage|vendor)/ {
        deny all;
    }

    location ~ /\. {
        deny all;
    }

    location ~ ^.+\.php {
        fastcgi_split_path_info ^(.+?\.php)(/.*)\$;
        fastcgi_pass unix:${PHP_SOCK};
        fastcgi_index index.php;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
    }
}
EOF
nginx_enable_site "easyappointments"
msg_ok "Configured Nginx"

msg_info "Creating Easy!Appointments Admin"
CSRF_TOKEN=$(curl -fsS -c - -o /dev/null http://127.0.0.1/index.php/installation | awk '$6 == "csrf_cookie" {print $7}')
$STD curl -fsS -b "csrf_cookie=${CSRF_TOKEN}" http://127.0.0.1/index.php/installation/perform \
  --data-urlencode "csrf_token=${CSRF_TOKEN}" \
  --data-urlencode "admin[first_name]=Admin" \
  --data-urlencode "admin[last_name]=User" \
  --data-urlencode "admin[email]=${var_admin_email}" \
  --data-urlencode "admin[username]=${var_admin_user}" \
  --data-urlencode "admin[password]=${var_admin_pass}" \
  --data-urlencode "admin[language]=english" \
  --data-urlencode "company[company_name]=Company Name" \
  --data-urlencode "company[company_email]=${var_admin_email}" \
  --data-urlencode "company[company_link]=http://${LOCAL_IP}"
mkdir -p /opt/easyappointments_data
cat <<EOF >/opt/easyappointments_data/.env
EA_ADMIN_USERNAME=${var_admin_user}
EA_ADMIN_EMAIL=${var_admin_email}
EA_ADMIN_PASSWORD=${var_admin_pass}
EOF
chmod 600 /opt/easyappointments_data/.env
msg_ok "Created Easy!Appointments Admin"

msg_info "Setting up Cron"
cat <<EOF >/etc/cron.d/easyappointments
0 * * * * www-data php /opt/easyappointments/index.php console sync >/dev/null 2>&1
30 3 * * * www-data php /opt/easyappointments/index.php console cleanup >/dev/null 2>&1
EOF
systemctl enable -q --now cron
msg_ok "Set up Cron"

motd_ssh
customize
cleanup_lxc
