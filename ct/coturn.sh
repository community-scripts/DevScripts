#!/usr/bin/env bash
_CS_DEFAULT_URL="https://raw.githubusercontent.com/community-scripts/DevScripts/main"
_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../core}/core/build.func"
source "$_cs_boot" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/build.func")
# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://github.com/coturn/coturn

APP="Coturn"
var_tags="${var_tags:-network;webrtc;turn}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-512}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"
var_testurl="${var_testurl:-https://github.com/community-scripts/DevScripts/issues/2654}"

export var_coturn_realm="${var_coturn_realm:-}"
export var_coturn_secret="${var_coturn_secret:-}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -f /usr/local/bin/turnserver ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "coturn" "coturn/coturn"; then
    msg_info "Stopping Coturn"
    systemctl stop coturn
    msg_ok "Stopped Coturn"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "coturn" "coturn/coturn" "tarball"

    msg_info "Building Coturn"
    cd /opt/coturn
    $STD ./configure --prefix=/usr/local --turndbdir=/opt/coturn_data --sysconfdir=/etc/coturn --disable-rpath
    $STD make -j"$(nproc)"
    $STD make install
    msg_ok "Built Coturn"

    msg_info "Starting Coturn"
    systemctl start coturn
    msg_ok "Started Coturn"
    msg_ok "Updated successfully!"
  fi
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW}TURN/STUN is listening on (UDP+TCP, TLS on 5349):${CL}"
echo -e "${GATEWAY}${BGN}turn:${IP}:3478${CL}"
echo -e "${INFO}${YW}Shared secret: /opt/coturn_data/.env${CL}"
