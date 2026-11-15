#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://github.com/mage-ai/mage-ai

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

PYTHON_VERSION="3.12" setup_uv

MAGE_VERSION="${var_appversion:-$(get_latest_github_release "mage-ai/mage-ai")}"
msg_info "Installing Mage ${MAGE_VERSION}"
$STD uv venv --seed --python 3.12 /opt/mage-ai/.venv
$STD uv pip install --python /opt/mage-ai/.venv/bin/python "mage-ai==${MAGE_VERSION}"
cat <<EOF >~/.mage-ai
${MAGE_VERSION}
EOF
msg_ok "Installed Mage ${MAGE_VERSION}"

msg_info "Configuring Mage"
mkdir -p /opt/mage-ai_data/mage_data
cat <<EOF >/opt/mage-ai_data/.env
MAGE_DATA_DIR=/opt/mage-ai_data/mage_data
REQUIRE_USER_AUTHENTICATION=1
DEFAULT_OWNER_EMAIL=admin@admin.com
DEFAULT_OWNER_USERNAME=admin
DEFAULT_OWNER_PASSWORD=${var_mage_password:-$(random_password)}
JWT_SECRET=$(random_password 64)
EOF
chmod 600 /opt/mage-ai_data/.env
$STD env MAGE_DATA_DIR=/opt/mage-ai_data/mage_data MAGE_REPO_PATH=/opt/mage-ai_data/default_repo /opt/mage-ai/.venv/bin/mage init /opt/mage-ai_data/default_repo
sed -i 's/^help_improve_mage: true/help_improve_mage: false/' /opt/mage-ai_data/default_repo/metadata.yaml
msg_ok "Configured Mage"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/mage-ai.service
[Unit]
Description=Mage
After=network.target

[Service]
Type=simple
WorkingDirectory=/opt/mage-ai_data
EnvironmentFile=/opt/mage-ai_data/.env
Environment=PATH=/opt/mage-ai/.venv/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
ExecStart=/opt/mage-ai/.venv/bin/mage start /opt/mage-ai_data/default_repo --host 0.0.0.0 --port 6789
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now mage-ai
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc
