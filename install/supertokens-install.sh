#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://github.com/supertokens/supertokens-core

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

setup_postgresql
PG_DB_NAME="supertokens" PG_DB_USER="supertokens" PG_DB_CREDS_FILE="/dev/null" setup_postgresql_db

ST_VERSION="${var_appversion:-$(get_latest_github_release "supertokens/supertokens-core")}"
ST_VERSION="${ST_VERSION#v}"
fetch_and_deploy_from_url "https://api.supertokens.com/0/app/download?pluginName=postgresql&os=$(arch_resolve "linux" "linux-arm")&mode=PRODUCTION&binary=FREE&targetCore=${ST_VERSION}" /opt/supertokens

msg_info "Downloading SuperTokens Dependencies"
# the zip ships its JRE without exec bits
chmod +x /opt/supertokens/jre/bin/* /opt/supertokens/jre/lib/jspawnhelper
cd /opt/supertokens
$STD ./jre/bin/java -classpath "./downloader/*" io.supertokens.downloader.Main
msg_ok "Downloaded SuperTokens Dependencies"
cat <<EOF >~/.supertokens
${ST_VERSION}
EOF

msg_info "Configuring SuperTokens"
var_api_key="${var_api_key:-$(random_password 32)}"
mkdir -p /opt/supertokens_data
cat <<EOF >/opt/supertokens_data/.env
API_KEY=${var_api_key}
DB_NAME=supertokens
DB_USER=supertokens
DB_PASSWORD=${PG_DB_PASS}
EOF
cat <<EOF >/opt/supertokens_data/config.yaml
core_config_version: 0
host: "0.0.0.0"
port: 3567
api_keys: "${var_api_key}"
postgresql_connection_uri: "postgresql://supertokens:${PG_DB_PASS}@localhost:5432/supertokens"
info_log_path: "null"
error_log_path: "null"
EOF
chmod 600 /opt/supertokens_data/.env /opt/supertokens_data/config.yaml
msg_ok "Configured SuperTokens"

msg_info "Creating SuperTokens Service"
cat <<EOF >/etc/systemd/system/supertokens.service
[Unit]
Description=SuperTokens Core
Wants=network-online.target
After=network-online.target postgresql.service

[Service]
Type=simple
WorkingDirectory=/opt/supertokens
ExecStart=/opt/supertokens/jre/bin/java -Djava.security.egd=file:/dev/urandom -classpath "/opt/supertokens/core/*:/opt/supertokens/plugin-interface/*:/opt/supertokens/ee/*" io.supertokens.Main /opt/supertokens/ configFile=/opt/supertokens_data/config.yaml
Restart=on-failure
SuccessExitStatus=143

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now supertokens
msg_ok "Created SuperTokens Service"

motd_ssh
customize
cleanup_lxc
