#!/usr/bin/env bash
_CS_DEFAULT_URL="https://raw.githubusercontent.com/community-scripts/DevScripts/main"
_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../core}/core/build.func"
source "$_cs_boot" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/build.func")
# Copyright (c) 2021-2026 community-scripts ORG
# Author: vavallee (vavallee)
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://github.com/vavallee/bindery

APP="Bindery"
var_tags="${var_tags:-arr;ebook;audiobook}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/bindery ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "bindery" "vavallee/bindery"; then
    msg_info "Stopping Bindery"
    systemctl stop bindery
    msg_ok "Stopped Bindery"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "bindery" "vavallee/bindery" "prebuild" "latest" "/opt/bindery" "bindery_*_linux_$(arch_resolve "amd64" "arm64").tar.gz"

    msg_info "Starting Bindery"
    systemctl start bindery
    msg_ok "Started Bindery"
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
echo -e "${GATEWAY}${BGN}http://${IP}:8787${CL}"
