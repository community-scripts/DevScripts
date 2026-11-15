#!/usr/bin/env bash
_CS_DEFAULT_URL="https://raw.githubusercontent.com/community-scripts/DevScripts/main"
_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../core}/core/build.func"
source "$_cs_boot" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/build.func")
# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://github.com/siyuan-note/siyuan

APP="SiYuan"
var_tags="${var_tags:-notes;knowledge-base;markdown}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-6}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"
var_testurl="${var_testurl:-https://github.com/community-scripts/DevScripts/issues/2609}"

export var_auth_code="${var_auth_code:-}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/siyuan ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "siyuan" "siyuan-note/siyuan"; then
    msg_info "Stopping SiYuan"
    systemctl stop siyuan
    msg_ok "Stopped SiYuan"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "siyuan" "siyuan-note/siyuan" "prebuild" "latest" "/opt/siyuan" "siyuan-*-$(arch_resolve "linux" "linux-arm64").tar.gz"

    msg_info "Removing SiYuan Desktop Files"
    find /opt/siyuan -mindepth 1 -maxdepth 1 ! -name resources -exec rm -rf {} +
    rm -rf /opt/siyuan/resources/app
    msg_ok "Removed SiYuan Desktop Files"

    msg_info "Starting SiYuan"
    systemctl start siyuan
    msg_ok "Started SiYuan"
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
echo -e "${GATEWAY}${BGN}http://${IP}:6806${CL}"
echo -e "${INFO}${YW}Access auth code: /opt/siyuan_data/.env (inside the container)${CL}"
