#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: TaiKamilla
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://www.shopware.com/ | Github: https://github.com/shopware/shopware

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

if [[ -z "${var_admin_user:-}" ]]; then
  var_admin_user=$(prompt_input "Shopware admin username:" "admin" 60)
fi
var_admin_user="${var_admin_user:-admin}"
if [[ -z "${var_admin_pass:-}" ]]; then
  var_admin_pass=$(random_password 16)
fi
var_admin_email="${var_admin_email:-admin@example.com}"
var_opensearch="${var_opensearch:-yes}"

msg_info "Installing Dependencies"
$STD apt install -y \
  nginx \
  unzip
msg_ok "Installed Dependencies"

MARIADB_VERSION="12.3" setup_mariadb
MARIADB_DB_NAME="shopware" MARIADB_DB_USER="shopware" setup_mariadb_db
PHP_VERSION="8.5" PHP_FPM="YES" PHP_MEMORY_LIMIT="512M" PHP_MAX_EXECUTION_TIME="300" PHP_MODULE="soap,zstd" setup_php
setup_composer
NODE_VERSION="24" setup_nodejs

msg_info "Tuning MariaDB and PHP"
cat <<EOF >/etc/mysql/mariadb.conf.d/90-shopware.cnf
[mysqld]
max_allowed_packet = 64M
group_concat_max_len = 320000
sql_mode = STRICT_TRANS_TABLES,ERROR_FOR_DIVISION_BY_ZERO,NO_ENGINE_SUBSTITUTION
innodb_buffer_pool_size = 512M
EOF
safe_service_restart mariadb
cat <<EOF >/etc/php/8.5/mods-available/shopware.ini
zend.assertions = -1
zend.detect_unicode = 0
opcache.enable_file_override = 1
opcache.interned_strings_buffer = 20
opcache.max_accelerated_files = 20000
opcache.memory_consumption = 256
realpath_cache_size = 4096K
realpath_cache_ttl = 3600
EOF
$STD phpenmod shopware
msg_ok "Tuned MariaDB and PHP"

VALKEY_VERSION=$(get_latest_github_release "valkey-io/valkey")
fetch_and_deploy_from_url "https://download.valkey.io/releases/valkey-${VALKEY_VERSION}-noble-$(arch_resolve "x86_64" "arm64").tar.gz" "/opt/valkey"
cat <<EOF >~/.valkey
${VALKEY_VERSION}
EOF

msg_info "Configuring Valkey"
mkdir -p /etc/valkey
for inst in cache:6379 persistent:6380; do
  name="${inst%%:*}"
  port="${inst##*:}"
  cat <<EOF >"/etc/valkey/valkey-${name}.conf"
bind 127.0.0.1 -::1
port ${port}
protected-mode yes
daemonize no
supervised systemd
dir /var/lib/valkey-${name}
logfile ""
maxmemory-policy volatile-lru
EOF
done
cat <<EOF >>/etc/valkey/valkey-cache.conf
maxmemory 512mb
save ""
appendonly no
EOF
cat <<EOF >>/etc/valkey/valkey-persistent.conf
maxmemory 256mb
appendonly yes
appendfsync everysec
EOF
cat <<EOF >/etc/systemd/system/valkey@.service
[Unit]
Description=Valkey instance %i
After=network.target

[Service]
Type=notify
DynamicUser=yes
StateDirectory=valkey-%i
ExecStart=/opt/valkey/bin/valkey-server /etc/valkey/valkey-%i.conf
Restart=always
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now valkey@cache valkey@persistent
msg_ok "Configured Valkey"

if [[ "$var_opensearch" == "yes" ]]; then
  setup_deb822_repo \
    "opensearch" \
    "https://artifacts.opensearch.org/publickeys/opensearch-release.pgp" \
    "https://artifacts.opensearch.org/releases/bundle/opensearch/3.x/apt" \
    "stable" \
    "main"
  msg_info "Installing OpenSearch"
  OPENSEARCH_INITIAL_ADMIN_PASSWORD="$(random_password 24)Aa1!" $STD apt install -y opensearch
  cat <<EOF >/etc/opensearch/opensearch.yml
cluster.name: shopware
node.name: shopware
path.data: /var/lib/opensearch
path.logs: /var/log/opensearch
network.host: 127.0.0.1
http.port: 9200
discovery.type: single-node
plugins.security.disabled: true
EOF
  mkdir -p /etc/opensearch/jvm.options.d
  cat <<EOF >/etc/opensearch/jvm.options.d/heap.options
-Xms1g
-Xmx1g
EOF
  systemctl enable -q --now opensearch
  for _ in {1..60}; do curl -fsS http://127.0.0.1:9200 >/dev/null 2>&1 && break; sleep 2; done
  msg_ok "Installed OpenSearch"
fi

msg_info "Installing Shopware"
export COMPOSER_ALLOW_SUPERUSER=1
$STD composer create-project shopware/production /opt/shopware --no-interaction --no-dev --prefer-dist
cd /opt/shopware
$STD composer require --no-interaction --update-no-dev symfony/redis-messenger
rm -rf /opt/shopware/var/cache/*
ES_ENABLED=0
[[ "$var_opensearch" == "yes" ]] && ES_ENABLED=1
cat <<EOF >/opt/shopware/.env.local
APP_ENV=prod
APP_SECRET=$(random_password 64)
APP_URL=http://${LOCAL_IP}
DATABASE_URL=mysql://${MARIADB_DB_USER}:${MARIADB_DB_PASS}@localhost:3306/${MARIADB_DB_NAME}
MAILER_DSN=null://null
LOCK_DSN=redis://127.0.0.1:6380/3
REDIS_CACHE=redis://127.0.0.1:6379
REDIS_PERSISTENT=redis://127.0.0.1:6380
MESSENGER_TRANSPORT_DSN=redis://127.0.0.1:6380/shopware_async?dbindex=4&auto_setup=true
MESSENGER_TRANSPORT_LOW_PRIORITY_DSN=redis://127.0.0.1:6380/shopware_low_priority?dbindex=4&auto_setup=true
MESSENGER_TRANSPORT_FAILURE_DSN=redis://127.0.0.1:6380/shopware_failed?dbindex=4&auto_setup=true
SHOPWARE_HTTP_CACHE_ENABLED=1
SHOPWARE_HTTP_DEFAULT_TTL=7200
OPENSEARCH_URL=http://127.0.0.1:9200
SHOPWARE_ES_ENABLED=${ES_ENABLED}
SHOPWARE_ES_INDEXING_ENABLED=${ES_ENABLED}
SHOPWARE_ES_INDEX_PREFIX=sw
SHOPWARE_ES_THROW_EXCEPTION=0
ADMIN_OPENSEARCH_URL=http://127.0.0.1:9200
SHOPWARE_ADMIN_ES_ENABLED=${ES_ENABLED}
SHOPWARE_ADMIN_ES_REFRESH_INDICES=${ES_ENABLED}
SHOPWARE_ADMIN_ES_INDEX_PREFIX=sw-admin
EOF
mkdir -p config/packages/prod
cat <<'EOF' >config/packages/prod/zz-proxmox-shopware.yaml
framework:
    cache:
        app: cache.adapter.redis_tag_aware
        system: cache.adapter.redis_tag_aware
        default_redis_provider: '%env(REDIS_CACHE)%/0'
    session:
        handler_id: '%env(REDIS_PERSISTENT)%/1'
    mailer:
        message_bus: 'messenger.default_bus'

shopware:
    redis:
        connections:
            ephemeral:
                dsn: '%env(REDIS_CACHE)%/1?persistent=1'
            persistent:
                dsn: '%env(REDIS_PERSISTENT)%/2?persistent=1'
    admin_worker:
        enable_admin_worker: false
    cache:
        invalidation:
            delay_options:
                storage: redis
                connection: 'ephemeral'
    cart:
        compress: true
        compression_method: zstd
        storage:
            type: 'redis'
            config:
                connection: 'persistent'
    number_range:
        increment_storage: 'redis'
        config:
            connection: 'persistent'
    increment:
        user_activity:
            type: 'redis'
            config:
                connection: 'persistent'
        message_queue:
            type: 'redis'
            config:
                connection: 'persistent'

elasticsearch:
    index_settings:
        number_of_shards: 1
        number_of_replicas: 0

monolog:
    handlers:
        main:
            level: error
            buffer_size: 30
        business_event_handler_buffer:
            level: error
EOF
$STD php bin/console system:install --basic-setup --shop-locale=en-GB --shop-currency=EUR --shop-name="Shopware" --shop-email="${var_admin_email}" --no-interaction
$STD php bin/console user:change-password admin --password="${var_admin_pass}"
if [[ "$var_admin_user" != "admin" ]]; then
  $STD php bin/console user:create "${var_admin_user}" --admin --email="${var_admin_email}" --password="${var_admin_pass}" --firstName="Shop" --lastName="Admin"
  $STD php bin/console user:delete admin
fi
$STD php bin/console sales-channel:update:domain "${LOCAL_IP}"
if [[ "$ES_ENABLED" == "1" ]]; then
  $STD php bin/console es:index --no-queue
  $STD php bin/console es:admin:index --no-queue
fi
$STD php bin/console cache:clear
$STD php bin/console dotenv:dump prod
jq -r '.packages[] | select(.name == "shopware/core") | .version' /opt/shopware/composer.lock | sed 's/^v//' >~/.shopware
chown -R www-data:www-data /opt/shopware
msg_ok "Installed Shopware"

msg_info "Creating Nginx Site"
PHP_SOCK=$(get_php_fpm_socket)
cat <<EOF >/etc/nginx/sites-available/shopware
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _;

    root /opt/shopware/public;
    index index.php;

    client_max_body_size 128M;
    server_tokens off;

    gzip on;
    gzip_types text/plain text/css text/javascript application/javascript application/json image/svg+xml;
    gzip_min_length 1000;

    location /recovery/install {
        index index.php;
        try_files \$uri /recovery/install/index.php\$is_args\$args;
    }

    location ~ ^/(theme|media|thumbnail|bundles|css|fonts|js|recovery|sitemap)/ {
        expires 1y;
        add_header Cache-Control "public, must-revalidate, proxy-revalidate";
        log_not_found off;
        tcp_nodelay off;
        open_file_cache max=3000 inactive=120s;
        open_file_cache_valid 45s;
        open_file_cache_min_uses 2;
        open_file_cache_errors off;

        location ~* ^.+\.svg {
            add_header Content-Security-Policy "script-src 'none'";
            add_header Cache-Control "public, must-revalidate, proxy-revalidate";
            log_not_found off;
        }
    }

    location ~* ^.+\.(?:css|cur|js|jpe?g|gif|ico|png|svg|webp|avif|html|woff|woff2|xml)\$ {
        expires 1y;
        add_header Cache-Control "public, must-revalidate, proxy-revalidate";
        access_log off;
        tcp_nodelay off;
        try_files \$uri /index.php\$is_args\$args;
    }

    location / {
        try_files \$uri /index.php\$is_args\$args;
    }

    location ~ \.php\$ {
        fastcgi_split_path_info ^(.+\.php)(/.+)\$;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_param HTTP_PROXY "";
        fastcgi_buffers 8 16k;
        fastcgi_buffer_size 32k;
        fastcgi_read_timeout 300s;
        client_body_buffer_size 128k;
        fastcgi_pass unix:${PHP_SOCK};
    }

    location ~ /\.(?!well-known) {
        deny all;
    }
}
EOF
msg_ok "Created Nginx Site"
nginx_enable_site "shopware"

msg_info "Creating Services"
cat <<EOF >/etc/systemd/system/shopware-worker.service
[Unit]
Description=Shopware Message Queue Worker
After=network.target mariadb.service valkey@persistent.service

[Service]
Type=simple
User=www-data
WorkingDirectory=/opt/shopware
ExecStart=/usr/bin/php /opt/shopware/bin/console messenger:consume async low_priority failed --time-limit=360 --memory-limit=512M
Restart=always

[Install]
WantedBy=multi-user.target
EOF
cat <<EOF >/etc/systemd/system/shopware-scheduler.service
[Unit]
Description=Shopware Scheduled Task Runner
After=network.target mariadb.service valkey@persistent.service

[Service]
Type=simple
User=www-data
WorkingDirectory=/opt/shopware
ExecStart=/usr/bin/php /opt/shopware/bin/console scheduled-task:run --time-limit=360 --memory-limit=512M
Restart=always

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now shopware-worker shopware-scheduler
msg_ok "Created Services"

msg_info "Saving Credentials"
cat <<EOF >>~/shopware.creds

Shopware Admin
Username: ${var_admin_user}
Password: ${var_admin_pass}
EOF
chmod 600 ~/shopware.creds
msg_ok "Saved Credentials"

motd_ssh
customize
cleanup_lxc
