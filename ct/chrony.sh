#!/usr/bin/env bash
_CS_DEFAULT_URL="https://raw.githubusercontent.com/community-scripts/DevScripts/main"
_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../core}/core/build.func"
source "$_cs_boot" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/build.func")

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Jan Wiebe Klijnsma (jwklijnsma)
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://chrony-project.org/

APP="Chrony"
var_tags="${var_tags:-ntp;time;gps}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-512}"
var_disk="${var_disk:-2}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_unprivileged="${var_unprivileged:-0}"
#var_arm64="${var_arm64:-no}" # unset = ask the user; set yes/no only when verified
export var_gps_device="${var_gps_device:-}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -f /etc/chrony/conf.d/gps.conf ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  msg_info "Updating Chrony and gpsd"
  apt_update_safe
  upgrade_packages_with_retry chrony gpsd gpsd-clients
  systemctl restart chrony gpsd
  msg_ok "Updated Chrony and gpsd"
  msg_ok "Updated successfully!"
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW}Point your NTP clients at UDP port 123 and check the GPS lock with 'chronyc sources':${CL}"
echo -e "${GATEWAY}${BGN}${IP}:123${CL}"
