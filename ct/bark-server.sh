#!/usr/bin/env bash
_CS_DEFAULT_URL="https://raw.githubusercontent.com/community-scripts/DevScripts/main"
_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../core}/core/build.func"
source "$_cs_boot" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/build.func")
# Copyright (c) 2021-2026 community-scripts ORG
# Author: Charlie Smith (chazkii)
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://github.com/Finb/bark-server

APP="Bark-Server"
var_tags="${var_tags:-notification}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-256}"
var_disk="${var_disk:-2}"
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

  if [[ ! -d /opt/bark-server ]]; then
    msg_error "No Bark Server Installation Found!"
    exit
  fi

  if check_for_gh_release "bark-server" "Finb/bark-server"; then
    msg_info "Stopping Bark Server"
    systemctl stop bark-server
    msg_ok "Stopped Bark Server"

    create_backup /opt/bark-server/bark.db

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "bark-server" "Finb/bark-server" "singlefile" "latest" "/opt/bark-server" "bark-server_linux_$(arch_resolve "amd64" "armv8")"

    restore_backup

    msg_info "Starting Bark Server"
    systemctl start bark-server
    msg_ok "Started Bark Server"
    msg_ok "Updated successfully!"
  fi
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}Bark Server setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW}Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:8080/ping${CL}"
