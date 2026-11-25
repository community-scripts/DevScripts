#!/usr/bin/env bash
source "$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

APP="Immich Remote ML"
APP_DIR="/opt/immich-remote-ml"
DATA_DIR="/opt/immich-remote-ml_data"
ML_SOURCE_DIR="${APP_DIR}/machine-learning"
VENV_DIR="${DATA_DIR}/venv"
CACHE_DIR="${DATA_DIR}/cache"
HOME_DIR="${DATA_DIR}/home"

$STD apt install -y g++ git

PYTHON_VERSION="3.13" setup_uv
setup_hwaccel

fetch_and_deploy_gh_release "immich-remote-ml" "immich-app/immich" "tarball" "latest" "$APP_DIR"

if [[ "${HWACCEL_VENDOR:-none}" == "amd" ]]; then
  ML_EXTRA="rocm"
  DEVICE="rocm"
  $STD apt install -y rocm-hip-libraries rocm-ml-libraries
  msg_ok "AMD ROCm machine-learning backend selected"
else
  ML_EXTRA="cpu"
  DEVICE="cpu"
  msg_warn "No AMD GPU passthrough detected; using the CPU machine-learning backend"
fi

mkdir -p "$DATA_DIR" "$CACHE_DIR" "$HOME_DIR" "$VENV_DIR"

cat <<EOF >/etc/default/immich-remote-ml
ML_EXTRA=$ML_EXTRA
DEVICE=$DEVICE
# For unsupported gfx1030 GPUs, uncomment the following overrides if ROCm reports an architecture error.
# HSA_OVERRIDE_GFX_VERSION=10.3.0
# HSA_USE_SVM=0
EOF

UV_PROJECT_ENVIRONMENT="$VENV_DIR" $STD uv sync --project "$ML_SOURCE_DIR" --locked --no-dev --no-install-project --extra "$ML_EXTRA" --python 3.13 --link-mode copy

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
Environment=IMMICH_HOST=0.0.0.0
Environment=IMMICH_PORT=3003
Environment=MACHINE_LEARNING_CACHE_FOLDER=$CACHE_DIR
Environment=MACHINE_LEARNING_MODEL_ARENA=false
ExecStart=$VENV_DIR/bin/gunicorn immich_ml.main:app -k immich_ml.config.CustomUvicornWorker -c immich_ml/gunicorn_conf.py -b 0.0.0.0:3003 -w 1 -t 300 --log-config-json log_conf.json --keep-alive 2 --graceful-timeout 10 --no-control-socket
Restart=on-failure
RestartSec=5
TimeoutStartSec=300
TimeoutStopSec=30
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

systemctl enable --now immich-remote-ml.service

if systemctl is-active --quiet immich-remote-ml.service; then
  msg_ok "Immich Remote ML is listening on TCP port 3003"
else
  journalctl -u immich-remote-ml.service -n 50 --no-pager
  msg_error "Immich Remote ML failed to start"
  exit 1
fi

motd_ssh
customize
cleanup_lxc
