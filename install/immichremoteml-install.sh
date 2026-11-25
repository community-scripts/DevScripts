#!/usr/bin/env bash
source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
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
# Let the shared helper install userspace libraries matching the Proxmox host driver.
INSTALL_NVIDIA_DRIVERS=yes setup_hwaccel

fetch_and_deploy_gh_release "immich-remote-ml" "immich-app/immich" "tarball" "latest" "$APP_DIR"

case "${HWACCEL_VENDOR:-none}" in
  amd)
    ML_EXTRA="rocm"
    DEVICE="rocm"
    $STD apt install -y migraphx miopen-hip
    msg_ok "AMD ROCm machine-learning backend selected"
    ;;
  nvidia)
    ML_EXTRA="cuda"
    DEVICE="cuda"
    msg_ok "NVIDIA CUDA machine-learning backend selected"
    ;;
  *)
    ML_EXTRA="cpu"
    DEVICE="cpu"
    msg_warn "No supported GPU passthrough detected; using the CPU machine-learning backend"
    ;;
esac

mkdir -p "$DATA_DIR" "$CACHE_DIR/jit/comgr" "$CACHE_DIR/jit/cuda" "$CACHE_DIR/hf-cache" "$HOME_DIR" "$VENV_DIR"

cat <<EOF >/etc/default/immich-remote-ml
ML_EXTRA=$ML_EXTRA
DEVICE=$DEVICE
# For unsupported gfx1030 GPUs, uncomment the following overrides if ROCm reports an architecture error.
# HSA_OVERRIDE_GFX_VERSION=10.3.0
# HSA_USE_SVM=0
EOF

UV_SYNC_ARGS=(--project "$ML_SOURCE_DIR" --locked --no-dev --no-install-project --extra "$ML_EXTRA" --python 3.13 --link-mode copy)
if [[ "$ML_EXTRA" == "cuda" ]]; then
  # Immich's CUDA runtime libraries are separate from the ONNX Runtime CUDA extra.
  UV_SYNC_ARGS+=(--group cuda-libs)
fi
UV_PROJECT_ENVIRONMENT="$VENV_DIR" $STD uv sync "${UV_SYNC_ARGS[@]}"

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
Environment=CUDA_CACHE_PATH=$CACHE_DIR/jit/cuda
ExecStart=$VENV_DIR/bin/python -m immich_ml
Restart=on-failure
RestartSec=5
TimeoutStartSec=300
TimeoutStopSec=30
PrivateTmp=true
PrivateDevices=false
ProtectSystem=strict
ProtectHome=read-only
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
