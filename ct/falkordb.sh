#!/usr/bin/env bash
_CS_DEFAULT_URL="https://raw.githubusercontent.com/community-scripts/DevScripts/main"
_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../core}/core/build.func"
source "$_cs_boot" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/build.func")
# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://github.com/FalkorDB/FalkorDB

APP="FalkorDB"
var_tags="${var_tags:-database;graph}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-10}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"
var_testurl="${var_testurl:-https://github.com/community-scripts/DevScripts/issues/2352}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -f /opt/falkordb/falkordb ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "falkordb" "FalkorDB/FalkorDB"; then
    msg_info "Stopping FalkorDB"
    systemctl stop redis-server
    msg_ok "Stopped FalkorDB"

    fetch_and_deploy_gh_release "falkordb" "FalkorDB/FalkorDB" "singlefile" "latest" "/opt/falkordb" "falkordb-$(arch_resolve "x64" "arm64v8").so"

    msg_info "Starting FalkorDB"
    systemctl start redis-server
    msg_ok "Started FalkorDB"
    msg_ok "Updated FalkorDB successfully!"
  fi

  if check_for_gh_release "falkordb-browser" "FalkorDB/falkordb-browser"; then
    msg_info "Stopping FalkorDB Browser"
    systemctl stop falkordb-browser
    msg_ok "Stopped FalkorDB Browser"

    NODE_VERSION="24" setup_nodejs
    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "falkordb-browser" "FalkorDB/falkordb-browser" "tarball"

    msg_info "Building FalkorDB Browser"
    cd /opt/falkordb-browser
    $STD npm ci
    NEXT_TELEMETRY_DISABLED=1 $STD npm run build
    cp -r .next/static .next/standalone/.next/
    cp -r public .next/standalone/
    msg_ok "Built FalkorDB Browser"

    msg_info "Starting FalkorDB Browser"
    systemctl start falkordb-browser
    msg_ok "Started FalkorDB Browser"
    msg_ok "Updated FalkorDB Browser successfully!"
  fi
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW}Access the FalkorDB Browser using the following URL:${CL}"
echo -e "${GATEWAY}${BGN}http://${IP}:3000${CL}"
echo -e "${INFO}${YW}FalkorDB listens on port 6379 - the password is in /etc/redis/falkordb.conf${CL}"
