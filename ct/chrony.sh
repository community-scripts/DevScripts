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
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
if [[ -z "${var_ntp_stratum:-}" ]] && command -v pveversion >/dev/null 2>&1; then
  var_ntp_stratum=$(msg_menu "Choose the NTP stratum" \
    "1" "Stratum 1 - GPS receiver (privileged, USB passthrough)" \
    "2" "Stratum 2 - sync from public stratum 1 servers" \
    "3" "Stratum 3 - sync from the NTP pool or your own stratum 2")
fi
export var_ntp_stratum="${var_ntp_stratum:-1}"
if [[ "$var_ntp_stratum" == "1" ]]; then
  var_unprivileged="${var_unprivileged:-0}"
else
  var_unprivileged="${var_unprivileged:-1}"
fi
var_arm64="${var_arm64:-yes}"
export var_gps_device="${var_gps_device:-}"
export var_ntp_servers="${var_ntp_servers:-}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -f /etc/chrony/conf.d/server.conf ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  apt_update_safe
  if ! apt list --upgradable 2>/dev/null | grep -qE '^(chrony|gpsd|gpsd-clients)/'; then
    msg_ok "Chrony and gpsd are already up to date"
    exit
  fi

  msg_info "Updating Chrony"
  upgrade_packages_with_retry chrony
  systemctl restart chrony
  msg_ok "Updated Chrony"

  if [[ -f /etc/default/gpsd ]]; then
    msg_info "Updating gpsd"
    upgrade_packages_with_retry gpsd gpsd-clients
    systemctl restart gpsd
    msg_ok "Updated gpsd"
  fi
  msg_ok "Updated successfully!"
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW}Point your NTP clients at UDP port 123 and check the sources with 'chronyc sources':${CL}"
echo -e "${GATEWAY}${BGN}${IP}:123${CL}"
