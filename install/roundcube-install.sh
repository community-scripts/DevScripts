#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://github.com/roundcube/roundcubemail

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt install -y nginx rsync
msg_ok "Installed Dependencies"

PHP_VERSION="8.4" PHP_FPM="YES" PHP_MODULE="ldap" setup_php
fetch_and_deploy_gh_release "roundcube" "roundcube/roundcubemail" "prebuild" "latest" "/opt/roundcube" "roundcubemail-*-complete.tar.gz"

msg_info "Configuring Roundcube"
mkdir -p /opt/roundcube_data
cat <<EOF >/opt/roundcube/config/config.inc.php
<?php
\$config = [];
\$config['db_dsnw'] = 'sqlite:////opt/roundcube_data/roundcube.db?mode=0640';
\$config['imap_host'] = '${var_imap_host:-}';
\$config['smtp_host'] = '${var_smtp_host:-%h:587}';
\$config['smtp_user'] = '%u';
\$config['smtp_pass'] = '%p';
\$config['product_name'] = 'Roundcube Webmail';
\$config['des_key'] = '$(random_password 24)';
\$config['plugins'] = ['archive', 'zipdownload'];
\$config['skin'] = 'elastic';
EOF
rm -rf /opt/roundcube/installer
chown -R www-data:www-data /opt/roundcube /opt/roundcube_data
chmod 640 /opt/roundcube/config/config.inc.php
cd /opt/roundcube
$STD runuser -u www-data -- php bin/initdb.sh --dir=SQL --update
msg_ok "Configured Roundcube"

msg_info "Configuring Nginx"
PHP_SOCK=$(get_php_fpm_socket)
cat <<EOF >/etc/nginx/sites-available/roundcube
server {
    listen 80;
    listen [::]:80;
    server_name _;

    root /opt/roundcube/public_html;
    index index.php;

    client_max_body_size 128M;

    location = /favicon.ico {
        rewrite ^ /static.php/skins/elastic/images/favicon.ico last;
    }
    location / {
        try_files \$uri \$uri/ /index.php\$is_args\$args;
    }
    location ~ \.php(/|\$) {
        fastcgi_split_path_info ^(.+?\.php)(/.*)\$;
        set \$path_info \$fastcgi_path_info;
        try_files \$fastcgi_script_name =404;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_param PATH_INFO \$path_info;
        fastcgi_pass unix:${PHP_SOCK};
    }
    location ~ /\. {
        deny all;
    }
}
EOF
nginx_enable_site "roundcube"
msg_ok "Configured Nginx"

motd_ssh
customize
cleanup_lxc
