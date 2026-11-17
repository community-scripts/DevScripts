#!/usr/bin/env bash
_CS_DEFAULT_URL="https://raw.githubusercontent.com/community-scripts/DevScripts/main"
_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../core}/core/build.func"
source "$_cs_boot" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/build.func")

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Filan-glitch
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://sli.dev/

APP="Slidev"
var_tags="${var_tags:-presentation;markdown}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-6}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_unprivileged="${var_unprivileged:-1}"
#var_arm64="${var_arm64:-no}" # unset = ask the user; set yes/no only when verified

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/slidev/node_modules/@slidev/cli ]]; then
    msg_error "No Slidev Installation Found!"
    exit
  fi

  if check_for_gh_release "slidev" "slidevjs/slidev"; then
    NODE_VERSION="24" setup_nodejs

    msg_info "Stopping Slidev"
    systemctl stop slidev
    msg_ok "Stopped Slidev"

    msg_info "Updating Slidev"
    cd /opt/slidev
    $STD npm install "@slidev/cli@${CHECK_UPDATE_RELEASE#v}"
    $STD npm update
    cat <<EOF >~/.slidev
${CHECK_UPDATE_RELEASE#v}
EOF
    msg_ok "Updated Slidev"

    msg_info "Starting Slidev"
    systemctl start slidev
    msg_ok "Started Slidev"
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
echo -e "${GATEWAY}${BGN}http://${IP}:3030${CL}"
