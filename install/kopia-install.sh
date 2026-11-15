#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://github.com/kopia/kopia

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

fetch_and_deploy_gh_release "kopia" "kopia/kopia" "binary" "latest" "" "kopia_*_linux_$(arch_resolve "amd64" "arm64").deb"
create_self_signed_cert "kopia"

msg_info "Creating Kopia Repository"
mkdir -p /opt/kopia_data/{config,repository,cache,logs}
cat <<EOT >/opt/kopia_data/.env
KOPIA_CONFIG_PATH=/opt/kopia_data/config/repository.config
KOPIA_CACHE_DIRECTORY=/opt/kopia_data/cache
KOPIA_LOG_DIR=/opt/kopia_data/logs
KOPIA_PASSWORD=${var_kopia_repo_password:-$(random_password)}
KOPIA_SERVER_USERNAME=admin
KOPIA_SERVER_PASSWORD=${var_kopia_password:-$(random_password)}
KOPIA_SERVER_CONTROL_PASSWORD=$(random_password)
EOT
chmod 600 /opt/kopia_data/.env
set -a
source /opt/kopia_data/.env
set +a
$STD kopia repository create filesystem --path /opt/kopia_data/repository
msg_ok "Created Kopia Repository"

msg_info "Creating Service"
cat <<EOT >/etc/systemd/system/kopia.service
[Unit]
Description=Kopia Server
After=network-online.target
Wants=network-online.target

[Service]
EnvironmentFile=/opt/kopia_data/.env
ExecStart=/usr/bin/kopia server start --address=0.0.0.0:51515 --tls-cert-file=/etc/ssl/kopia/kopia.crt --tls-key-file=/etc/ssl/kopia/kopia.key
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOT
systemctl enable -q --now kopia
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc
