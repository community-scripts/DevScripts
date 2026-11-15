#!/usr/bin/env bash
_CS_DEFAULT_URL="https://raw.githubusercontent.com/community-scripts/DevScripts/main"
_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../core}/core/build.func"
source "$_cs_boot" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/build.func")
# Copyright (c) 2021-2026 community-scripts ORG
# Author: Leif Davisson (leifdavisson)
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://github.com/esnet/iperf

APP="iPerf3"
var_tags="${var_tags:-network;benchmark;iperf3}"
var_cpu="${var_cpu:-1}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

if [[ -z "${var_os:-}" ]] && command -v pveversion >/dev/null 2>&1; then
  var_os=$(msg_menu "Choose the container OS" \
    "debian" "Debian 13" \
    "alpine" "Alpine (smaller footprint)")
fi

if [[ "${var_os:-}" == "alpine" ]]; then
  var_ram="${var_ram:-256}"
  var_disk="${var_disk:-1}"
  var_version="${var_version:-3.24}"
else
  var_os="${var_os:-debian}"
  var_ram="${var_ram:-512}"
  var_disk="${var_disk:-2}"
  var_version="${var_version:-13}"
fi

header_info "$APP"
variables
color
catch_errors

update_deb_based() {
  msg_info "Updating iPerf3"
  $STD apt update
  $STD apt upgrade -y
  systemctl restart iperf3
  msg_ok "Updated iPerf3"
}

update_alpine() {
  msg_info "Updating iPerf3"
  $STD apk -U upgrade
  $STD rc-service iperf3 restart
  msg_ok "Updated iPerf3"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if ! command -v iperf3 >/dev/null 2>&1; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  run_os_update
  exit
}

start
build_container
description

msg_ok "Completed successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW}iPerf3 server is listening on port 5201:${CL}"
echo -e "${GATEWAY}${BGN}iperf3 -c ${IP}${CL}"
