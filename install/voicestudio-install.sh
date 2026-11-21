#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Estcool9
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://github.com/debpalash/VoiceStudio

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing VoiceStudio dependencies"
$STD apt install -y build-essential ffmpeg libsndfile1 libopus-dev pkg-config cmake python3-dev
msg_ok "Installed VoiceStudio dependencies"

mkdir -p /opt/voicestudio_data/uv/python /opt/voicestudio_data/huggingface
export UV_PYTHON_INSTALL_DIR=/opt/voicestudio_data/uv/python
fetch_and_deploy_gh_release "voicestudio" "debpalash/VoiceStudio" "tarball"
PYTHON_VERSION="3.11" setup_uv
NODE_VERSION="22" NODE_MODULE="$(jq -r '.packageManager' /opt/voicestudio/package.json)" setup_nodejs

msg_info "Building VoiceStudio"
cd /opt/voicestudio
$STD bun install --frozen-lockfile
$STD bun run setup:api
$STD bun run --cwd electron build:web
rm -rf /opt/voicestudio/node_modules /opt/voicestudio/electron/node_modules
msg_ok "Built VoiceStudio"

msg_info "Configuring VoiceStudio"
API_KEY="$(random_password 64)"
cat <<EOF >/opt/voicestudio_data/.env
OMNIVOICE_DATA_DIR=/opt/voicestudio_data
HF_HOME=/opt/voicestudio_data/huggingface
OMNIVOICE_SERVER_MODE=1
OMNIVOICE_BIND_HOST=0.0.0.0
OMNIVOICE_API_KEY=${API_KEY}
EOF
if [[ -n "${var_voicestudio_hf_token:-}" ]]; then
  cat <<EOF >>/opt/voicestudio_data/.env
HF_TOKEN=${var_voicestudio_hf_token}
EOF
fi
chmod 600 /opt/voicestudio_data/.env
msg_ok "Configured VoiceStudio"

msg_info "Creating VoiceStudio service"
cat <<EOF >/etc/systemd/system/voicestudio.service
[Unit]
Description=VoiceStudio Headless Backend
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/voicestudio
EnvironmentFile=/opt/voicestudio_data/.env
Environment=HOME=/opt/voicestudio_data
Environment=PYTHONPATH=/opt/voicestudio/backend
Environment=PYTHONUNBUFFERED=1
ExecStart=/opt/voicestudio/.venv/bin/uvicorn backend.main:app --host 0.0.0.0 --port 3900
Restart=on-failure
RestartSec=5
TimeoutStartSec=600
LimitNOFILE=65535
UMask=0077
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=full
ProtectHome=true
ReadWritePaths=/opt/voicestudio /opt/voicestudio_data

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now voicestudio
$STD curl --retry 60 --retry-delay 2 --retry-connrefused -fsS http://127.0.0.1:3900/health
msg_ok "Created VoiceStudio service"

cat <<EOF >/etc/systemd/system/voicestudio-update.service
[Unit]
Description=VoiceStudio stable release update
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/bin/update
SuccessExitStatus=1
EOF
cat <<EOF >/etc/systemd/system/voicestudio-update.timer
[Unit]
Description=Daily VoiceStudio stable release update check

[Timer]
OnCalendar=*-*-* 03:30:00
RandomizedDelaySec=45m
Persistent=true
Unit=voicestudio-update.service

[Install]
WantedBy=timers.target
EOF

motd_ssh
customize
systemctl enable -q --now voicestudio-update.timer
cleanup_lxc
