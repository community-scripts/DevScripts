#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Estcool9 (Estcool9)
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://github.com/debpalash/VoiceStudio

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing VoiceStudio system dependencies"
$STD apt install -y \
  build-essential \
  gnupg \
  libsndfile1
msg_ok "Installed VoiceStudio system dependencies"

setup_ffmpeg
NODE_VERSION="22" NODE_MODULE="bun@1.4.2" setup_nodejs
PYTHON_VERSION="3.11" setup_uv

fetch_and_deploy_gh_release "voicestudio" "debpalash/VoiceStudio" "tarball"

msg_info "Installing VoiceStudio JavaScript dependencies"
cd /opt/voicestudio
$STD bun install --frozen-lockfile
msg_ok "Installed VoiceStudio JavaScript dependencies"

msg_info "Installing VoiceStudio CPU backend"
OMNIVOICE_TORCH_VARIANT=cpu $STD bun run setup:api
msg_ok "Installed VoiceStudio CPU backend"

msg_info "Building VoiceStudio web interface"
$STD bun run build:web
msg_ok "Built VoiceStudio web interface"

msg_info "Configuring VoiceStudio data and model storage"
mkdir -p /opt/voicestudio_data/huggingface
chmod 700 /opt/voicestudio_data /opt/voicestudio_data/huggingface
cat <<EOF >/opt/voicestudio_data/.env
OMNIVOICE_SERVER_MODE=1
OMNIVOICE_API_KEY=$(random_password 48)
OMNIVOICE_DATA_DIR=/opt/voicestudio_data
HF_HOME=/opt/voicestudio_data/huggingface
PYTHONPATH=/opt/voicestudio/backend
PYTHONUNBUFFERED=1
PYTHONDONTWRITEBYTECODE=1
OMNIVOICE_ANALYTICS_DISABLED=1
EOF
chmod 600 /opt/voicestudio_data/.env
msg_ok "Configured VoiceStudio data and model storage"

msg_info "Creating VoiceStudio service"
cat <<EOF >/etc/systemd/system/voicestudio.service
[Unit]
Description=VoiceStudio Web Backend
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=/opt/voicestudio
EnvironmentFile=/opt/voicestudio_data/.env
ExecStart=/opt/voicestudio/.venv/bin/uvicorn backend.main:app --host 0.0.0.0 --port 3900
Restart=on-failure
RestartSec=5
TimeoutStartSec=600
UMask=0077
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now voicestudio
msg_ok "Created VoiceStudio service"

motd_ssh
customize
cleanup_lxc
