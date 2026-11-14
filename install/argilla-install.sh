#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://github.com/argilla-io/argilla

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt install -y valkey-server
msg_ok "Installed Dependencies"

setup_deb822_repo \
  "elasticsearch" \
  "https://artifacts.elastic.co/GPG-KEY-elasticsearch" \
  "https://artifacts.elastic.co/packages/8.x/apt" \
  "stable" \
  "main"

msg_info "Installing Elasticsearch"
$STD apt install -y elasticsearch
cat <<EOF >/etc/elasticsearch/elasticsearch.yml
cluster.name: argilla
path.data: /var/lib/elasticsearch
path.logs: /var/log/elasticsearch
network.host: 127.0.0.1
http.port: 9200
discovery.type: single-node
cluster.routing.allocation.disk.threshold_enabled: false
xpack.security.enabled: false
xpack.security.transport.ssl.enabled: false
xpack.security.http.ssl.enabled: false
EOF
cat <<EOF >/etc/elasticsearch/jvm.options.d/heap.options
-Xms512m
-Xmx512m
EOF
systemctl enable -q --now elasticsearch
msg_ok "Installed Elasticsearch"

PYTHON_VERSION="3.13" setup_uv

ARGILLA_VERSION="${var_appversion:-$(get_latest_github_release "argilla-io/argilla")}"
msg_info "Installing Argilla ${ARGILLA_VERSION#v}"
$STD uv venv --python 3.13 /opt/argilla/.venv
# argilla-server pins typer<0.10, which breaks with click 8.2+
$STD uv pip install --python /opt/argilla/.venv/bin/python "argilla-server==${ARGILLA_VERSION#v}" "click<8.2"
cat <<EOF >~/.argilla
${ARGILLA_VERSION#v}
EOF
msg_ok "Installed Argilla ${ARGILLA_VERSION#v}"

msg_info "Configuring Argilla"
mkdir -p /opt/argilla_data
cat <<EOF >/opt/argilla_data/.env
ARGILLA_HOME_PATH=/opt/argilla_data
ARGILLA_ELASTICSEARCH=http://127.0.0.1:9200
ARGILLA_REDIS_URL=redis://127.0.0.1:6379/0
ARGILLA_AUTH_SECRET_KEY=$(random_password 64)
HF_HUB_DISABLE_TELEMETRY=1
ADMIN_USERNAME=admin
ADMIN_PASSWORD=${var_argilla_password:-$(random_password)}
ADMIN_API_KEY=${var_argilla_api_key:-$(random_password 32)}
EOF
chmod 600 /opt/argilla_data/.env
cd /opt/argilla_data
set -a && source /opt/argilla_data/.env && set +a
$STD /opt/argilla/.venv/bin/python -m argilla_server database migrate
$STD /opt/argilla/.venv/bin/python -m argilla_server database users create --first-name admin --username admin --password "${ADMIN_PASSWORD}" --api-key "${ADMIN_API_KEY}" --role owner --workspace default
msg_ok "Configured Argilla"

msg_info "Creating Services"
cat <<EOF >/etc/systemd/system/argilla.service
[Unit]
Description=Argilla Server
After=network.target elasticsearch.service valkey-server.service
Requires=elasticsearch.service valkey-server.service

[Service]
Type=simple
WorkingDirectory=/opt/argilla_data
EnvironmentFile=/opt/argilla_data/.env
ExecStart=/opt/argilla/.venv/bin/python -m uvicorn argilla_server:app --host 0.0.0.0 --port 6900
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
cat <<EOF >/etc/systemd/system/argilla-worker.service
[Unit]
Description=Argilla Worker
After=network.target valkey-server.service argilla.service
Requires=valkey-server.service

[Service]
Type=simple
WorkingDirectory=/opt/argilla_data
EnvironmentFile=/opt/argilla_data/.env
ExecStart=/opt/argilla/.venv/bin/python -m argilla_server worker
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now argilla argilla-worker
msg_ok "Created Services"

motd_ssh
customize
cleanup_lxc
