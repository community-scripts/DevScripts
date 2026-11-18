#!/usr/bin/env bash
_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../core}/core/build.func"
source "$_cs_boot" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/build.func")

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Jack B-W (jackB-W)
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://github.com/ZimengXiong/PancakeSlicer

APP="PancakeSlicer"
var_tags="${var_tags:-3d-printing}"
var_cpu="${var_cpu:-4}"
var_ram="${var_ram:-8192}"
var_disk="${var_disk:-10}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
#var_arm64="${var_arm64:-no}" # arm64 releases exist, but haven't tested yet. CI workflow can check it serves, probably worth a manual test to make sure it slices.
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/pancakeslicer ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "pancakeslicer" "ZimengXiong/PancakeSlicer"; then
    msg_info "Stopping PancakeSlicer"
    systemctl stop pancakeslicer
    msg_ok "Stopped PancakeSlicer"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "pancakeslicer" "ZimengXiong/PancakeSlicer" "prebuild" "latest" "/opt/pancakeslicer" "PancakeSlicer-*-linux-$(arch_resolve "x64" "arm64").tar.gz"

    msg_info "Updating PancakeSlicer"
    sed -i "s|^Environment=ORCA_WEB_SOURCE_URL=.*|Environment=ORCA_WEB_SOURCE_URL=https://github.com/ZimengXiong/PancakeSlicer/releases/tag/v$(cat ~/.pancakeslicer)|" /etc/systemd/system/pancakeslicer.service
    systemctl daemon-reload
    msg_ok "Updated PancakeSlicer"

    msg_info "Starting PancakeSlicer"
    systemctl start pancakeslicer
    msg_ok "Started PancakeSlicer"
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
echo -e "${GATEWAY}${BGN}http://${IP}:6868${CL}"
