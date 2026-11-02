#!/usr/bin/env bash
_CS_DEFAULT_URL="https://raw.githubusercontent.com/community-scripts/DevScripts/main"
_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../core}/core/build.func"
source "$_cs_boot" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/build.func")
# Copyright (c) 2021-2026 community-scripts ORG
# Author: TechJeeper (TechJeeper)
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://printventory.com | https://github.com/TechJeeper/Printventory

APP="Printventory"
var_tags="${var_tags:-3dprinting;inventory;models}"
var_cpu="${var_cpu:-4}"
var_ram="${var_ram:-8192}"
var_disk="${var_disk:-20}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-no}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/printventory ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_branch "printventory" "TechJeeper/Printventory" "main"; then
    msg_info "Stopping Printventory"
    systemctl stop printventory
    msg_ok "Stopped Printventory"

    fetch_and_deploy_gh_branch "printventory" "TechJeeper/Printventory" "main"

    msg_info "Updating Printventory Dependencies (Patience)"
    cd /opt/printventory
    $STD npm install --ignore-scripts
    $STD npx --yes @electron/rebuild --version="$(node -p 'require("electron/package.json").version')" || $STD npx electron-builder install-app-deps
    chmod +x /opt/printventory/scripts/run-server.sh
    msg_ok "Updated Printventory Dependencies"

    msg_info "Starting Printventory"
    systemctl start printventory
    msg_ok "Started Printventory"
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
echo -e "${GATEWAY}${BGN}http://${IP}:5000${CL}"
