#!/usr/bin/env bash
_CS_DEFAULT_URL="https://raw.githubusercontent.com/community-scripts/DevScripts/main"
_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../core}/core/build.func"
source "$_cs_boot" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/build.func")
# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://github.com/dragonflydb/dragonfly

APP="Dragonfly"
var_tags="${var_tags:-database;cache}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"
var_testurl="${var_testurl:-https://github.com/community-scripts/DevScripts/issues/2350}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -f /usr/bin/dragonfly ]]; then
    msg_error "No Dragonfly Installation Found!"
    exit
  fi

  if check_for_gh_release "dragonfly" "dragonflydb/dragonfly"; then
    msg_info "Stopping Dragonfly"
    systemctl stop dragonfly
    msg_ok "Stopped Dragonfly"

    DPKG_FORCE_CONFOLD=1 fetch_and_deploy_gh_release "dragonfly" "dragonflydb/dragonfly" "binary"

    msg_info "Starting Dragonfly"
    $STD systemctl daemon-reload
    systemctl start dragonfly
    msg_ok "Started Dragonfly"
    msg_ok "Updated successfully!"
  fi
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW}Connect with redis-cli, the password is --requirepass in /etc/dragonfly/dragonfly.conf:${CL}"
echo -e "${GATEWAY}${BGN}redis-cli -h ${IP} -p 6379 -a <password>${CL}"
