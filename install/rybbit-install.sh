#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://github.com/rybbit-io/rybbit

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

var_base_url="${var_base_url:-https://${LOCAL_IP}}"

msg_info "Installing Dependencies"
$STD apt install -y \
  nginx \
  redis-server
msg_ok "Installed Dependencies"

PG_VERSION="17" setup_postgresql
PG_DB_NAME="rybbit" PG_DB_USER="rybbit" PG_DB_CREDS_FILE="/dev/null" setup_postgresql_db
setup_clickhouse
NODE_VERSION="24" setup_nodejs

msg_info "Configuring ClickHouse and Redis"
CLICKHOUSE_PASS=$(random_password)
REDIS_PASS=$(random_password)
cat <<EOF >/etc/clickhouse-server/config.d/rybbit.xml
<clickhouse>
  <logger><level>warning</level></logger>
  <query_thread_log remove="remove"/>
  <query_log remove="remove"/>
  <query_views_log remove="remove"/>
  <query_metric_log remove="remove"/>
  <opentelemetry_span_log remove="remove"/>
  <text_log remove="remove"/>
  <trace_log remove="remove"/>
  <metric_log remove="remove"/>
  <asynchronous_metric_log remove="remove"/>
  <session_log remove="remove"/>
  <part_log remove="remove"/>
  <latency_log remove="remove"/>
  <processors_profile_log remove="remove"/>
  <max_server_memory_usage_to_ram_ratio>0.80</max_server_memory_usage_to_ram_ratio>
  <merges_mutations_memory_usage_to_ram_ratio>0.25</merges_mutations_memory_usage_to_ram_ratio>
</clickhouse>
EOF
cat <<EOF >/etc/clickhouse-server/users.d/rybbit.xml
<clickhouse>
  <users>
    <default>
      <password>${CLICKHOUSE_PASS}</password>
      <access_management>1</access_management>
    </default>
  </users>
  <profiles>
    <default>
      <enable_json_type>1</enable_json_type>
      <async_insert>1</async_insert>
      <wait_for_async_insert>1</wait_for_async_insert>
      <log_queries>0</log_queries>
    </default>
  </profiles>
</clickhouse>
EOF
rm -f /etc/clickhouse-server/users.d/default-password.xml
chown -R clickhouse:clickhouse /etc/clickhouse-server/config.d /etc/clickhouse-server/users.d
systemctl restart clickhouse-server
for _ in {1..30}; do
  clickhouse-client --password "$CLICKHOUSE_PASS" -q "SELECT 1" &>/dev/null && break
  sleep 2
done
clickhouse-client --password "$CLICKHOUSE_PASS" -q "CREATE DATABASE IF NOT EXISTS analytics"
sed -i "s/^# requirepass .*/requirepass ${REDIS_PASS}/" /etc/redis/redis.conf
systemctl restart redis-server
msg_ok "Configured ClickHouse and Redis"

fetch_and_deploy_gh_release "rybbit" "rybbit-io/rybbit" "tarball"

msg_info "Configuring Rybbit"
mkdir -p /opt/rybbit_data
cat <<EOF >/opt/rybbit_data/.env
NODE_ENV=production
BASE_URL=${var_base_url%/}
BETTER_AUTH_SECRET=$(random_password 64)
DISABLE_SIGNUP=false
DISABLE_TELEMETRY=true
POSTGRES_HOST=127.0.0.1
POSTGRES_PORT=5432
POSTGRES_DB=rybbit
POSTGRES_USER=rybbit
POSTGRES_PASSWORD=${PG_DB_PASS}
CLICKHOUSE_HOST=http://127.0.0.1:8123
CLICKHOUSE_DB=analytics
CLICKHOUSE_PASSWORD=${CLICKHOUSE_PASS}
CLICKHOUSE_QUERY_PASSWORD=$(random_password)
REDIS_HOST=127.0.0.1
REDIS_PORT=6379
REDIS_PASSWORD=${REDIS_PASS}
MAPBOX_TOKEN=
EOF
chmod 600 /opt/rybbit_data/.env
msg_ok "Configured Rybbit"

msg_info "Building Rybbit"
cd /opt/rybbit/shared
$STD npm install
$STD npm run build
cd /opt/rybbit/server
PUPPETEER_SKIP_DOWNLOAD=true $STD npm ci --legacy-peer-deps
rm -rf node_modules/@rybbit/shared
mkdir -p node_modules/@rybbit/shared
cp -r /opt/rybbit/shared/package.json /opt/rybbit/shared/dist node_modules/@rybbit/shared/
$STD npm run build
cd /opt/rybbit/client
$STD npm ci --legacy-peer-deps
rm -rf node_modules/@rybbit/shared
mkdir -p node_modules/@rybbit/shared
cp -r /opt/rybbit/shared/package.json /opt/rybbit/shared/dist node_modules/@rybbit/shared/
NEXT_TELEMETRY_DISABLED=1 NEXT_PUBLIC_BACKEND_URL="" NEXT_PUBLIC_DISABLE_SIGNUP=false $STD npm run build
cp -r public .next/standalone/
cp -r .next/static .next/standalone/.next/
rm -rf node_modules .next/cache ~/.npm
msg_ok "Built Rybbit"

msg_info "Creating Services"
cat <<EOF >/etc/systemd/system/rybbit-server.service
[Unit]
Description=Rybbit Server
After=network-online.target postgresql.service clickhouse-server.service redis-server.service
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=/opt/rybbit/server
EnvironmentFile=/opt/rybbit_data/.env
ExecStartPre=/usr/bin/npm run db:migrate
ExecStart=/usr/bin/node dist/cluster.js
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
cat <<EOF >/etc/systemd/system/rybbit-client.service
[Unit]
Description=Rybbit Client
After=network-online.target rybbit-server.service

[Service]
Type=simple
WorkingDirectory=/opt/rybbit/client/.next/standalone
Environment=NODE_ENV=production
Environment=PORT=3002
Environment=HOSTNAME=127.0.0.1
ExecStart=/usr/bin/node server.js
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
create_self_signed_cert "rybbit"
cat <<EOF >/etc/nginx/sites-available/rybbit
map \$scheme\$http_x_forwarded_proto \$rybbit_redirect {
    default 0;
    http 1;
    httphttp 1;
}

server {
    listen 80;
    listen 443 ssl;
    server_name _;
    ssl_certificate /etc/ssl/rybbit/rybbit.crt;
    ssl_certificate_key /etc/ssl/rybbit/rybbit.key;
    client_max_body_size 10M;

    if (\$rybbit_redirect) {
        return 301 https://\$host\$request_uri;
    }

    location ~ ^/(api/|\.well-known/oauth-|\.well-known/openid-configuration) {
        proxy_pass http://127.0.0.1:3001;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
    }

    location / {
        proxy_pass http://127.0.0.1:3002;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
EOF
nginx_enable_site "rybbit"
systemctl enable -q --now rybbit-server rybbit-client
msg_ok "Created Services"

motd_ssh
customize
cleanup_lxc
