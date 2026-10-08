#!/usr/bin/env bash
# Engine comes from community-scripts/core; this repo only ships the scripts.
# A local core checkout wins (COMMUNITY_SCRIPTS_CORE_DIR, else a sibling ../core),
# so a fork or branch of core can be tested without editing this file.
_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../core}/core/build.func"
source "$_cs_boot" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/build.func")
# Copyright (c) 2021-2026 community-scripts ORG
# Author: william-aqn
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://www.rocket.chat/

APP="Rocket.Chat"
var_tags="${var_tags:-chat;messaging}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-20}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

export var_admin_email="${var_admin_email:-}"

header_info "$APP"
variables
NSAPP="rocketchat"
var_install="${NSAPP}-install"
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/rocketchat ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  RELEASE=$(curl -fsSL https://releases.rocket.chat/latest/info | jq -r '.tag')
  if [[ "${RELEASE}" != "$(cat ~/.rocketchat 2>/dev/null)" ]]; then
    msg_info "Stopping Service"
    systemctl stop rocketchat
    msg_ok "Stopped Service"

    CLEAN_INSTALL=1 fetch_and_deploy_from_url "https://releases.rocket.chat/${RELEASE}/download" "/opt/rocketchat"
    echo "${RELEASE}" >~/.rocketchat

    msg_info "Building Rocket.Chat ${RELEASE} (Patience)"
    cd /opt/rocketchat/programs/server
    $STD npm install
    msg_ok "Built Rocket.Chat ${RELEASE}"

    msg_info "Starting Service"
    systemctl start rocketchat
    msg_ok "Started Service"
    msg_ok "Updated Successfully!"
  else
    msg_ok "No update required. Rocket.Chat is already at ${RELEASE}"
  fi
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW}Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:3000${CL}"
echo -e "${INFO}${YW}Admin credentials: ~/rocketchat.creds (inside the container)${CL}"
