#!/usr/bin/env bash
_CS_DEFAULT_URL="https://raw.githubusercontent.com/community-scripts/DevScripts/main"
_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../core}/core/build.func"
source "$_cs_boot" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/build.func")

# Copyright (c) 2021-2026 community-scripts ORG
# Author: andy-vdg
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://hindsight.vectorize.io/

APP="Hindsight"
var_tags="${var_tags:-ai;memory;mcp}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-12}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
#var_arm64="${var_arm64:-no}" # unset = ask the user; set yes/no only when verified
var_unprivileged="${var_unprivileged:-1}"

export var_llm_provider="${var_llm_provider:-}"
export var_llm_api_key="${var_llm_api_key:-}"
export var_llm_model="${var_llm_model:-}"
export var_llm_base_url="${var_llm_base_url:-}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/hindsight ]]; then
    msg_error "No Hindsight Installation Found!"
    exit
  fi

  if check_for_gh_release "hindsight" "vectorize-io/hindsight"; then
    msg_info "Stopping Hindsight"
    systemctl stop hindsight
    msg_ok "Stopped Hindsight"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "hindsight" "vectorize-io/hindsight" "tarball"
    PYTHON_VERSION="3.11" UV_PROJECT_DIR="/opt/hindsight" setup_uv

    msg_info "Updating Python Environment"
    cd /opt/hindsight
    $STD uv sync --locked --package hindsight-api-slim --extra local-ml
    msg_ok "Updated Python Environment"

    msg_info "Starting Hindsight"
    systemctl start hindsight
    msg_ok "Started Hindsight"
    msg_ok "Updated successfully!"
  fi
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW}Access the API and its interactive docs using the following URL:${CL}"
echo -e "${GATEWAY}${BGN}http://${IP}:8888/docs${CL}"
echo -e "${INFO}${YW}API key: ~/hindsight.creds (inside the container)${CL}"
