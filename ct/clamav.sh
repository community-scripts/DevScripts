#!/usr/bin/env bash
_CS_DEFAULT_URL="https://raw.githubusercontent.com/community-scripts/DevScripts/main"
_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../core}/core/build.func"
source "$_cs_boot" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/build.func")
# Copyright (c) 2021-2026 community-scripts ORG
# Author: Jan Wiebe Klijnsma (jwklijnsma)
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://www.clamav.net

APP="ClamAV"
var_tags="${var_tags:-security;antivirus}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-8}"
var_os="${var_os:-ubuntu}"
var_version="${var_version:-26.04}"
#var_arm64="${var_arm64:-no}" # unset = ask the user; set yes/no only when verified
var_unprivileged="${var_unprivileged:-1}"

export var_scan_dir="${var_scan_dir:-}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -f /etc/clamav/clamd.conf ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  msg_info "Updating ClamAV"
  $STD apt update
  $STD apt install -y --only-upgrade clamav clamav-daemon clamav-freshclam
  systemctl restart clamav-daemon
  msg_ok "Updated ClamAV"
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW}Bind-mount the folders to scan to the scan folder you chose (default /mnt/scan), e.g. on the host:${CL}"
echo -e "${TAB}${BGN}pct set <CTID> -mp0 /path/on/host,mp=${var_scan_dir:-/mnt/scan},ro=1${CL}"
echo -e "${INFO}${YW}Daily scan results: /var/log/clamav/scan.log${CL}"
