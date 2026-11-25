#!/usr/bin/env bash
_CS_DEFAULT_URL="https://raw.githubusercontent.com/community-scripts/DevScripts/main"
_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../core}/core/build.func"
source "$_cs_boot" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/build.func")

# Copyright (c) 2021-2026 community-scripts ORG
# Author: jwklijnsma (jwklijnsma)
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://immich.app | https://github.com/immich-app/immich

APP="Immich Remote ML"
var_tags="${var_tags:-photos;ai}"
var_cpu="${var_cpu:-6}"
var_ram="${var_ram:-12288}"
var_disk="${var_disk:-50}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-no}" # ROCm and Immich's ROCm ONNX Runtime are amd64-only.
var_unprivileged="${var_unprivileged:-1}"
var_gpu="${var_gpu:-yes}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  local APP_DIR="/opt/immich-remote-ml"
  local DATA_DIR="/opt/immich-remote-ml_data"
  local ML_SOURCE_DIR="${APP_DIR}/machine-learning"
  local VENV_DIR="${DATA_DIR}/venv"

  if [[ ! -d "$ML_SOURCE_DIR" ]]; then
    msg_error "No ${APP} installation found!"
    exit
  fi

  if check_for_gh_release "immich-remote-ml" "immich-app/immich"; then
    msg_info "Stopping ${APP}"
    systemctl stop immich-remote-ml
    msg_ok "Stopped ${APP}"

    set -a
    source /etc/default/immich-remote-ml
    set +a

    msg_info "Updating ${APP}"
    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "immich-remote-ml" "immich-app/immich" "tarball" "latest" "$APP_DIR"
    UV_PROJECT_ENVIRONMENT="$VENV_DIR" $STD uv sync --project "$ML_SOURCE_DIR" --locked --no-dev --no-install-project --extra "${ML_EXTRA:-cpu}" --python 3.13 --link-mode copy
    msg_ok "Updated ${APP}"

    msg_info "Starting ${APP}"
    safe_service_restart "immich-remote-ml"
    msg_ok "Started ${APP}"
  fi
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW}Immich Machine Learning API is available at:${CL}"
echo -e "${GATEWAY}${BGN}http://${IP}:3003${CL}"
