#!/usr/bin/env bash
_CS_DEFAULT_URL="https://raw.githubusercontent.com/community-scripts/DevScripts/main"
_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../core}/core/build.func"
source "$_cs_boot" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/build.func")
# Copyright (c) 2021-2026 community-scripts ORG
# Author: Manel (manel)
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://github.com/amule-org/amule

APP="aMule"
var_tags="${var_tags:-p2p;ed2k}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-512}"
var_disk="${var_disk:-8}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"
export var_amule_password="${var_amule_password:-}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/amule ]]; then
    msg_error "No aMule Installation Found!"
    exit
  fi

  if check_for_gh_release "amule" "amule-org/amule"; then
    msg_info "Stopping aMule"
    systemctl stop amuled
    msg_ok "Stopped aMule"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "amule" "amule-org/amule" "prebuild" "latest" "/opt/amule" "aMule-*-Linux-$(arch_resolve "x64" "arm64")-static.tar.gz"

    msg_info "Starting aMule"
    systemctl start amuled
    msg_ok "Started aMule"
    msg_ok "Updated successfully!"
  fi
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW}Access it using the following URL:${CL}"
echo -e "${GATEWAY}${BGN}http://${IP}:4713${CL}"
echo -e "${INFO}${YW}Web UI password: AMULE_WEB_PASSWORD in /opt/amule_data/.env${CL}"
