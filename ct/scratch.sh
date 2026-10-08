#!/usr/bin/env bash
_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../core}/core/build.func"
source "$_cs_boot" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/build.func")
# Copyright (c) 2021-2026 community-scripts ORG
# Author: ma-world
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/scratchfoundation/scratch-editor

APP="Scratch"
var_tags="${var_tags:-education;programming}"
var_cpu="${var_cpu:-4}"
var_ram="${var_ram:-6144}"
var_disk="${var_disk:-8}"
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

  if [[ ! -d /opt/scratch-editor ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "scratch-editor" "scratchfoundation/scratch-editor"; then
    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "scratch-editor" "scratchfoundation/scratch-editor" "tarball"

    msg_info "Building Scratch"
    export NODE_OPTIONS="--max-old-space-size=2560"
    export PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1
    cd /opt/scratch-editor
    $STD npm install
    $STD npm run build
    rm -rf /var/www/scratch
    cp -a /opt/scratch-editor/packages/scratch-gui/build /var/www/scratch
    systemctl reload nginx
    msg_ok "Built Scratch"
  fi
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW}Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}${CL}"
