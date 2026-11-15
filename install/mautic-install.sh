#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://github.com/mautic/mautic

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

var_admin_user="${var_admin_user:-admin}"
var_admin_email="${var_admin_email:-admin@example.com}"
if [[ ! "$var_admin_email" =~ ^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$ ]]; then
  msg_warn "Invalid admin email '${var_admin_email}', using admin@example.com"
  var_admin_email="admin@example.com"
fi
var_admin_pass="${var_admin_pass:-$(random_password 16)}"

msg_info "Installing Dependencies"
$STD apt install -y nginx cron
msg_ok "Installed Dependencies"

setup_mariadb
MARIADB_DB_NAME="mautic" MARIADB_DB_USER="mautic" MARIADB_DB_CREDS_FILE="/dev/null" setup_mariadb_db
PHP_VERSION="8.4" PHP_MODULE="imap" PHP_FPM="YES" setup_php
fetch_and_deploy_gh_release "mautic" "mautic/mautic" "prebuild" "latest" "/opt/mautic" "*[0-9].zip"

msg_info "Configuring Mautic"
mkdir -p /opt/mautic_data
cat <<EOF >/opt/mautic_data/.env
MAUTIC_ADMIN_USER=${var_admin_user}
MAUTIC_ADMIN_EMAIL=${var_admin_email}
MAUTIC_ADMIN_PASSWORD=${var_admin_pass}
DB_NAME=mautic
DB_USER=mautic
DB_PASSWORD=${MARIADB_DB_PASS}
EOF
chmod 600 /opt/mautic_data/.env
sed -i "s|^;\?date.timezone =.*|date.timezone = UTC|" /etc/php/8.4/{cli,fpm}/php.ini
rm -f /opt/mautic/deleted_files.txt
chown -R www-data:www-data /opt/mautic
cd /opt/mautic
$STD runuser -u www-data -- php bin/console mautic:install "http://${LOCAL_IP}" --force \
  --db_driver=pdo_mysql --db_host=localhost --db_port=3306 --db_name=mautic --db_user=mautic \
  --db_password="$MARIADB_DB_PASS" --db_backup_tables=false \
  --admin_username="$var_admin_user" --admin_email="$var_admin_email" --admin_password="$var_admin_pass"
runuser -u www-data -- env SMTP_HOST="${var_smtp_host:-}" SMTP_PORT="${var_smtp_port:-587}" \
  SMTP_USER="${var_smtp_user:-}" SMTP_PASS="${var_smtp_pass:-}" FROM="$var_admin_email" php -r '
$f = "/opt/mautic/config/local.php";
include $f;
$auth = getenv("SMTP_USER") !== "" ? rawurlencode(getenv("SMTP_USER")).":".rawurlencode(getenv("SMTP_PASS"))."@" : "";
$parameters["mailer_dsn"] = getenv("SMTP_HOST") !== "" ? "smtp://".$auth.getenv("SMTP_HOST").":".getenv("SMTP_PORT") : "null://null";
$parameters["mailer_from_email"] = getenv("FROM");
$parameters["mailer_from_name"] = "Mautic";
file_put_contents($f, "<?php\n\$parameters = ".var_export($parameters, true).";\n");
'
$STD runuser -u www-data -- php bin/console cache:clear
msg_ok "Configured Mautic"

msg_info "Configuring Nginx"
PHP_SOCK=$(get_php_fpm_socket)
cat <<EOF >/etc/nginx/sites-available/mautic
server {
    listen 80;
    listen [::]:80;
    server_name _;

    root /opt/mautic;
    index index.php;
    client_max_body_size 128M;

    location ~ /\. {
        deny all;
    }
    location ~ ^/(bin|config|translations|var|media/files)/ {
        deny all;
    }
    location ~ ^/app/(?!assets/|bundles/) {
        deny all;
    }
    location ~* \.(yml|yaml|twig|lock|txt|md|dist|sql|neon)\$ {
        deny all;
    }
    location ~ ^/composer\.json\$ {
        deny all;
    }
    location / {
        try_files \$uri /index.php\$is_args\$args;
    }
    location ~ ^/index\.php(/|\$) {
        fastcgi_split_path_info ^(.+\.php)(/.*)\$;
        fastcgi_pass unix:${PHP_SOCK};
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_param HTTP_AUTHORIZATION \$http_authorization;
        fastcgi_read_timeout 300;
    }
    location ~ \.php\$ {
        deny all;
    }
}
EOF
nginx_enable_site "mautic"
msg_ok "Configured Nginx"

msg_info "Setting up Cron"
cat <<EOF >/etc/cron.d/mautic
0,15,30,45 * * * * www-data php /opt/mautic/bin/console mautic:segments:update >/dev/null 2>&1
5,20,35,50 * * * * www-data php /opt/mautic/bin/console mautic:campaigns:update >/dev/null 2>&1
10,25,40,55 * * * * www-data php /opt/mautic/bin/console mautic:campaigns:trigger >/dev/null 2>&1
*/5 * * * * www-data php /opt/mautic/bin/console mautic:broadcasts:send >/dev/null 2>&1
*/5 * * * * www-data php /opt/mautic/bin/console mautic:messages:send >/dev/null 2>&1
*/5 * * * * www-data php /opt/mautic/bin/console mautic:import >/dev/null 2>&1
*/15 * * * * www-data php /opt/mautic/bin/console mautic:webhooks:process >/dev/null 2>&1
*/15 * * * * www-data php /opt/mautic/bin/console mautic:reports:scheduler >/dev/null 2>&1
0 3 * * * www-data php /opt/mautic/bin/console mautic:maintenance:cleanup --days-old=365 --no-interaction >/dev/null 2>&1
EOF
systemctl enable -q --now cron
msg_ok "Set up Cron"

motd_ssh
customize
cleanup_lxc
