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
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
#var_arm64="${var_arm64:-no}" # unset = ask the user; set yes/no only when verified
var_unprivileged="${var_unprivileged:-1}"

export var_scan_dir="${var_scan_dir:-}"
export var_scan_mode="${var_scan_mode:-}"
export var_clamd_tcp="${var_clamd_tcp:-}"
var_scan_host_dir="${var_scan_host_dir:-}"

header_info "$APP"
variables
color
catch_errors

# Checked before the build: a bad host path should fail in seconds, not after the install
if [[ -n "$var_scan_host_dir" ]] && [[ ! -d "$var_scan_host_dir" || "$var_scan_host_dir" == *[,=]* ]]; then
  msg_error "var_scan_host_dir must be an existing host folder without ',' or '=', got: ${var_scan_host_dir}"
  exit 1
fi

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

scan_dir="${var_scan_dir:-/mnt/scan}"
if command -v pct &>/dev/null; then
  # The scan folder may have been chosen at the prompt inside the container, so read it back
  scan_dir=$(pct exec "$CTID" -- sed -n 's/^Description=ClamAV scan of //p' /etc/systemd/system/clamav-scan.service)
  if [[ -z "$var_scan_host_dir" ]]; then
    var_scan_host_dir=$(prompt_input "Host folder to bind-mount read-only into ${scan_dir} (empty to skip):" "" 60)
  fi
  if [[ -n "$var_scan_host_dir" ]] && [[ ! -d "$var_scan_host_dir" || "$var_scan_host_dir" == *[,=]* ]]; then
    msg_warn "Skipped the bind mount: ${var_scan_host_dir} is not a host folder (or contains ',' or '=')"
    var_scan_host_dir=""
  fi
  if [[ -n "$var_scan_host_dir" ]]; then
    msg_info "Mounting ${var_scan_host_dir} into ClamAV"
    mp=0
    while pct config "$CTID" | grep -q "^mp${mp}:"; do
      mp=$((mp + 1))
    done
    pct set "$CTID" "-mp${mp}" "${var_scan_host_dir},mp=${scan_dir},ro=1"
    # The watcher must start on the mounted folder, not the empty one underneath it
    pct reboot "$CTID"
    msg_ok "Mounted ${var_scan_host_dir} into ClamAV (mp${mp}, read-only)"
  fi
fi

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
if [[ -z "$var_scan_host_dir" ]]; then
  echo -e "${INFO}${YW}Bind-mount the folders to scan into ${scan_dir}, e.g. on the host:${CL}"
  echo -e "${TAB}${BGN}pct set ${CTID} -mp0 /path/on/host,mp=${scan_dir},ro=1 && pct reboot ${CTID}${CL}"
fi
echo -e "${INFO}${YW}Scan results (watch and daily): /var/log/clamav/scan.log${CL}"
echo -e "${INFO}${YW}If TCP mode is enabled, point clients (Nextcloud, rspamd, clamav-milter) at:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}${IP}:3310${CL}"
echo -e "${INFO}${YW}clamd has no authentication: allow port 3310 only from those clients (e.g. the Proxmox firewall).${CL}"
