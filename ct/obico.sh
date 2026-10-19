#!/usr/bin/env bash
_CS_DEFAULT_URL="https://raw.githubusercontent.com/community-scripts/DevScripts/main"
_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../core}/core/build.func"
source "$_cs_boot" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/build.func")
# Copyright (c) 2021-2026 community-scripts ORG
# Author: a55uka (a55uka)
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://github.com/TheSpaghettiDetective/obico-server

APP="Obico"
var_tags="${var_tags:-3d-printing;monitoring;ai}"
var_cpu="${var_cpu:-4}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-15}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
#var_arm64="${var_arm64:-yes}" # unset = ask the user; set yes/no only when verified
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/obico ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_branch "obico" "TheSpaghettiDetective/obico-server" "release"; then
    msg_info "Stopping Services"
    systemctl stop obico-tasks obico-web obico-ml-api
    msg_ok "Stopped Services"

    create_backup /opt/obico/.env

    # No CLEAN_INSTALL: db.sqlite3, media, static_build, .venv and .env are
    # gitignored in the upstream repo and survive reset --hard + clean -fd.
    fetch_and_deploy_gh_branch "obico" "TheSpaghettiDetective/obico-server" "release" "/opt/obico"
    sed -i "s/^VERSION=.*/VERSION=$(cat ~/.obico)/" /opt/obico/.env

    MOONRAKER_SHA=$(grep -oP 'checkout \K[a-f0-9]{40}' /opt/obico/backend/Dockerfile.base)
    if [[ -n "$MOONRAKER_SHA" && "$(git -C /opt/moonraker rev-parse HEAD 2>/dev/null)" != "$MOONRAKER_SHA" ]]; then
      msg_info "Updating Moonraker Metadata Library"
      [[ -d /opt/moonraker/.git ]] || $STD git clone https://github.com/Arksine/moonraker.git /opt/moonraker
      $STD git -C /opt/moonraker fetch --depth 1 origin "$MOONRAKER_SHA"
      $STD git -C /opt/moonraker checkout "$MOONRAKER_SHA"
      msg_ok "Updated Moonraker Metadata Library"
    fi

    msg_info "Updating Python Environments"
    cd /opt/obico/backend
    $STD uv pip install -p .venv/bin/python -r requirements.txt
    $STD uv pip install -p .venv/bin/python importlib_metadata==8.2.0
    cd /opt/obico/ml_api
    $STD uv pip install -p .venv/bin/python -r requirements.txt onnxruntime==1.31.0 opencv-python-headless==4.12.0.88
    msg_ok "Updated Python Environments"

    if [[ "$(tr -d '\r' </opt/obico/ml_api/model/model-weights.onnx.sha256)" != "$(sha256sum /model_cache/ml_api/onnx/model-weights.onnx | cut -d' ' -f1)" ]]; then
      msg_info "Downloading Failure Detection Model"
      bash /opt/obico/ml_api/scripts/fetch_verified.sh "$(tr -d '\r' </opt/obico/ml_api/model/model-weights.onnx.url)" /model_cache/ml_api/onnx/model-weights.onnx 50000000 "$(tr -d '\r' </opt/obico/ml_api/model/model-weights.onnx.sha256)"
      msg_ok "Downloaded Failure Detection Model"
    fi

    msg_info "Running Database Migrations"
    set -a
    source /opt/obico/.env
    set +a
    cd /opt/obico/backend
    $STD .venv/bin/python manage.py migrate --noinput
    $STD .venv/bin/python manage.py collectstatic --noinput
    msg_ok "Ran Database Migrations"

    msg_info "Starting Services"
    systemctl start obico-ml-api obico-web obico-tasks
    msg_ok "Started Services"
    msg_ok "Updated successfully!"
  fi
  exit
}

start
build_container
description

msg_ok "Completed successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW}Access it using the following URL:${CL}"
echo -e "${GATEWAY}${BGN}http://${IP}:3334${CL}"
