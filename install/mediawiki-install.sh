#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://www.mediawiki.org/

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

var_admin_user="${var_admin_user:-Admin}"
var_wiki_name="${var_wiki_name:-My Wiki}"
var_admin_pass="${var_admin_pass:-$(random_password 16)}"
if [[ ${#var_admin_pass} -lt 10 ]]; then
  msg_warn "MediaWiki requires at least 10 characters for the admin password, generating one"
  var_admin_pass=$(random_password 16)
fi

msg_info "Installing Dependencies"
$STD apt install -y \
  nginx \
  imagemagick \
  ghostscript \
  poppler-utils \
  python3 \
  lua5.1
msg_ok "Installed Dependencies"

setup_mariadb
MARIADB_DB_NAME="mediawiki" MARIADB_DB_USER="mediawiki" MARIADB_DB_CREDS_FILE="/dev/null" setup_mariadb_db
PHP_VERSION="8.3" PHP_FPM="YES" setup_php

# LTS line: updates stay on it, a new LTS is a manual major upgrade
MW_VERSION="${var_appversion:-$(get_latest_gh_tag "wikimedia/mediawiki" "1.43.")}"
fetch_and_deploy_from_url "https://releases.wikimedia.org/mediawiki/${MW_VERSION%.*}/mediawiki-${MW_VERSION}.tar.gz" "/opt/mediawiki"

msg_info "Configuring MediaWiki"
mkdir -p /opt/mediawiki_data
mv /opt/mediawiki/images /opt/mediawiki_data/images
ln -s /opt/mediawiki_data/images /opt/mediawiki/images
cd /opt/mediawiki
$STD php maintenance/run.php install \
  --dbtype=mysql \
  --dbserver=localhost \
  --dbname=mediawiki \
  --dbuser=mediawiki \
  --dbpass="$MARIADB_DB_PASS" \
  --installdbuser=mediawiki \
  --installdbpass="$MARIADB_DB_PASS" \
  --server="http://${LOCAL_IP}" \
  --scriptpath="" \
  --lang=en \
  --pass="$var_admin_pass" \
  --with-extensions \
  --confpath=/opt/mediawiki_data \
  "$var_wiki_name" "$var_admin_user"
sed -i 's/^\$wgEnableUploads = false;/$wgEnableUploads = true;/' /opt/mediawiki_data/LocalSettings.php
cat <<'EOF' >>/opt/mediawiki_data/LocalSettings.php

$wgArticlePath = "/wiki/$1";
$wgScribuntoEngineConf['luastandalone']['luaPath'] = '/usr/bin/lua5.1';
EOF
ln -s /opt/mediawiki_data/LocalSettings.php /opt/mediawiki/LocalSettings.php
chown -R www-data:www-data /opt/mediawiki_data/images
chown root:www-data /opt/mediawiki_data/LocalSettings.php
chmod 640 /opt/mediawiki_data/LocalSettings.php
cat <<EOF >/opt/mediawiki_data/.env
MW_ADMIN_USER=${var_admin_user}
MW_ADMIN_PASS=${var_admin_pass}
EOF
chmod 600 /opt/mediawiki_data/.env
echo "$MW_VERSION" >~/.mediawiki
msg_ok "Configured MediaWiki"

msg_info "Configuring Nginx"
PHP_SOCK=$(get_php_fpm_socket)
cat <<EOF >/etc/nginx/sites-available/mediawiki
server {
    listen 80;
    listen [::]:80;
    server_name _;

    root /opt/mediawiki;
    index index.php;
    client_max_body_size 128M;

    location ~ ^/(cache|includes|languages|maintenance|mw-config|tests|vendor)/ {
        deny all;
    }
    location ~ /\.(ht|git|svn) {
        deny all;
    }
    location ^~ /images/deleted/ {
        deny all;
    }
    location ^~ /images/ {
        add_header X-Content-Type-Options nosniff;
        try_files \$uri =404;
    }
    location ~ \.php(/|\$) {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:${PHP_SOCK};
    }
    location /wiki/ {
        rewrite ^ /index.php;
    }
}
EOF
nginx_enable_site "mediawiki"
msg_ok "Configured Nginx"

motd_ssh
customize
cleanup_lxc
