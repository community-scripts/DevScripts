#!/usr/bin/env bash
_CS_DEFAULT_URL="https://raw.githubusercontent.com/community-scripts/DevScripts/main"
_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../core}/core/build.func"
source "$_cs_boot" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/build.func")
# Copyright (c) 2021-2026 community-scripts ORG
# Author: Gentleman-Programming
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://github.com/Gentleman-Programming/gentle-shell

APP="gentle-shell"
var_tags="${var_tags:-development;ai;coding-agent}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-10}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"
var_testurl="${var_testurl:-https://github.com/community-scripts/DevScripts/issues/NEW}"

var_hostname="${var_hostname:-}"
var_projects_mode="${var_projects_mode:-internal}"
var_projects_storage="${var_projects_storage:-}"
var_projects_size="${var_projects_size:-10}"
var_gh_token="${var_gh_token:-}"

header_info "$APP"
variables
color
catch_errors

if [[ -z "${var_hostname}" ]]; then
  read -rp "  Machine name for Herdr (default: gentle-shell): " -t 60 var_hostname || var_hostname=""
fi
var_hostname="${var_hostname:-gentle-shell}"

if [[ -z "${var_projects_mode}" ]]; then
  read -rp "  Store projects [1] inside the LXC disk or [2] on an external Proxmox mountpoint (default: 1): " -t 60 var_projects_mode || var_projects_mode="1"
fi
case "${var_projects_mode}" in
  2 | external) var_projects_mode="external" ;;
  *) var_projects_mode="internal" ;;
esac

if [[ "${var_projects_mode}" == "external" ]]; then
  if [[ -z "${var_projects_storage}" ]]; then
    read -rp "  Proxmox storage for the projects mountpoint (default: local-lvm): " -t 60 var_projects_storage || var_projects_storage=""
  fi
  var_projects_storage="${var_projects_storage:-local-lvm}"
  if ! pvesm status 2>/dev/null | awk 'NR>1 {print $1}' | grep -qx "${var_projects_storage}"; then
    msg_error "Storage '${var_projects_storage}' does not exist on this Proxmox host!"
    exit 1
  fi
  if [[ -z "${var_projects_size}" ]]; then
    read -rp "  Projects volume size in GB (default: 10): " -t 60 var_projects_size || var_projects_size=""
  fi
  var_projects_size="${var_projects_size:-10}"
fi

export var_hostname var_projects_mode var_projects_storage var_projects_size var_gh_token

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if ! command -v gentle-shell &>/dev/null; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  RELEASE=$(npm view gentle-pi version 2>/dev/null)
  if [[ -z "${RELEASE}" ]]; then
    msg_error "Unable to reach npm for the latest gentle-pi version."
    exit
  fi
  msg_info "Updating ${APP} (gentle-pi@${RELEASE})"
  $STD npm install -g "gentle-pi@${RELEASE}"
  msg_ok "Updated ${APP}"
  exit
}

start
build_container

if [[ "${var_projects_mode}" == "external" ]]; then
  msg_info "Attaching Projects Volume (${var_projects_storage}:${var_projects_size}GB)"
  pct set "${CTID}" -mp0 "${var_projects_storage}:${var_projects_size},mp=/mnt/projects"
  if ! pct exec "${CTID}" -- test -d /mnt/projects 2>/dev/null; then
    pct reboot "${CTID}"
    pct wait "${CTID}" running
  fi
  pct exec "${CTID}" -- ln -sfn /mnt/projects /root/projects
  msg_ok "Attached Projects Volume"
fi

description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW}Connect via SSH (root) and run 'gentle-shell'; projects live in /root/projects.${CL}"
