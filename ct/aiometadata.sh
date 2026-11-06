#!/usr/bin/env bash
_CS_DEFAULT_URL="https://raw.githubusercontent.com/community-scripts/DevScripts/main"
_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../core}/core/build.func"
source "$_cs_boot" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/build.func")
# Copyright (c) 2021-2026 community-scripts ORG
# Author: MrNRod
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://github.com/cedya77/aiometadata

APP="AIOMetadata"
var_tags="${var_tags:-media;streaming;stremio}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-8}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
#var_arm64="${var_arm64:-no}" # unset = ask the user; set yes/no only when verified
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/aiometadata ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "aiometadata" "cedya77/aiometadata" "" "" "v"; then
    msg_info "Stopping AIOMetadata"
    systemctl stop aiometadata
    msg_ok "Stopped AIOMetadata"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "aiometadata" "cedya77/aiometadata" "tarball" "latest" "" "" "v"

    msg_info "Building AIOMetadata"
    cd /opt/aiometadata
    $STD npm ci
    $STD npm run build
    $STD npm run build:backend
    msg_ok "Built AIOMetadata"

    msg_info "Starting AIOMetadata"
    systemctl start aiometadata
    msg_ok "Started AIOMetadata"
    msg_ok "Updated successfully!"
  fi
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Configure page (add to Stremio from here):${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:3232/configure${CL}"
echo -e "${INFO}${YW} Env file (API keys, admin key, Redis/DB config):${CL} ${BGN}/opt/aiometadata_data/.env${CL}"
