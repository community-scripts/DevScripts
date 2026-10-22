#!/usr/bin/env bash
_CS_DEFAULT_URL="https://raw.githubusercontent.com/community-scripts/DevScripts/main"
_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../core}/core/build.func"
source "$_cs_boot" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/build.func")
# Copyright (c) 2021-2026 community-scripts ORG
# Author: masterde
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://github.com/browseros-ai/BrowserOS

APP="BrowserOS-Neo"
var_tags="${var_tags:-browser;ai;mcp}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-10}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-no}" # GitHub releases ship an amd64 .deb only
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -f /etc/systemd/system/browseros-neo.service ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "browseros-neo" "browseros-ai/BrowserOS" "" "" "browserclaw/v"; then
    msg_info "Stopping BrowserOS Neo"
    systemctl stop browseros-neo
    msg_ok "Stopped BrowserOS Neo"

    fetch_and_deploy_gh_release "browseros-neo" "browseros-ai/BrowserOS" "binary" "latest" "" "" "browserclaw/v"

    msg_info "Starting BrowserOS Neo"
    systemctl start browseros-neo
    msg_ok "Started BrowserOS Neo"
    msg_ok "Updated successfully!"
  fi
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Open the browser viewer (user: neo) using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:6080${CL}"
echo -e "${INFO}${YW} Connect MCP clients to the following URL with an Authorization: Bearer header:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:9010/mcp${CL}"
echo -e "${INFO}${YW} The viewer password and MCP token are in /opt/browseros-neo_data/.env${CL}"
