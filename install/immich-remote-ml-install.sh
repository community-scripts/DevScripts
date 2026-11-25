#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: jwklijnsma (jwklijnsma)
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://immich.app | https://github.com/immich-app/immich

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

APP_DIR="/opt/immich-remote-ml"
DATA_DIR="/opt/immich-remote-ml_data"
ML_SOURCE_DIR="${APP_DIR}/machine-learning"
VENV_DIR="${DATA_DIR}/venv"
CACHE_DIR="${DATA_DIR}/cache"
HOME_DIR="${DATA_DIR}/home"

if [[ "$(get_os_info id)" != "debian" || "$(get_os_info codename)" != "trixie" ]]; then
  msg_error "Immich Remote ML currently requires Debian 13 (Trixie)."
  exit 1
fi

if [[ "$(arch_resolve)" != "amd64" ]]; then
  msg_error "Immich Remote ML ROCm acceleration currently requires amd64."
  exit 1
fi

$STD apt install -y g++ git

PYTHON_VERSION="3.13" setup_uv
setup_hwaccel

fetch_and_deploy_gh_release "immich-remote-ml" "immich-app/immich" "tarball" "latest" "$APP_DIR"

if [[ "${HWACCEL_VENDOR:-none}" == "amd" ]]; then
  ML_EXTRA="rocm"
  DEVICE="rocm"
  $STD apt install -y migraphx miopen-hip
  msg_ok "Configured AMD ROCm machine-learning backend"
else
  ML_EXTRA="cpu"
  DEVICE="cpu"
  msg_warn "No AMD ROCm GPU detected; using the CPU machine-learning backend"
fi

mkdir -p "$DATA_DIR" "$CACHE_DIR/jit/comgr" "$CACHE_DIR/hf-cache" "$HOME_DIR" "$VENV_DIR"

cat <<EOF >/etc/default/immich-remote-ml
ML_EXTRA=$ML_EXTRA
DEVICE=$DEVICE
EOF

UV_PROJECT_ENVIRONMENT="$VENV_DIR" $STD uv sync --project "$ML_SOURCE_DIR" --locked --no-dev --no-install-project --extra "$ML_EXTRA" --python 3.13 --link-mode copy

msg_info "Creating Immich Remote ML service"
cat <<EOF >/etc/systemd/system/immich-remote-ml.service
[Unit]
Description=Immich Remote Machine Learning
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=$ML_SOURCE_DIR
EnvironmentFile=-/etc/default/immich-remote-ml
Environment=HOME=$HOME_DIR
Environment=PATH=$VENV_DIR/bin:/opt/rocm/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
Environment=IMMICH_HOST=0.0.0.0
Environment=IMMICH_PORT=3003
Environment=MACHINE_LEARNING_CACHE_FOLDER=$CACHE_DIR
Environment=MACHINE_LEARNING_MODEL_REVISION=v2
Environment=HF_HOME=$CACHE_DIR/hf-cache
Environment=AMD_COMGR_CACHE_DIR=$CACHE_DIR/jit/comgr
ExecStart=$VENV_DIR/bin/python -m immich_ml
Restart=on-failure
RestartSec=10
TimeoutStartSec=300
TimeoutStopSec=30
KillMode=control-group
PrivateTmp=true
PrivateDevices=false
ProtectSystem=strict
ProtectHome=true
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true
NoNewPrivileges=true
RestrictSUIDSGID=true
LockPersonality=true
RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6
ReadWritePaths=$DATA_DIR

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now immich-remote-ml.service
msg_ok "Created Immich Remote ML service"

if ! systemctl is-active --quiet immich-remote-ml.service; then
  journalctl -u immich-remote-ml.service -n 50 --no-pager
  msg_error "Immich Remote ML failed to start"
  exit 1
fi

motd_ssh
customize
cleanup_lxc
