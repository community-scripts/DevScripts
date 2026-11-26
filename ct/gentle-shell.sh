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
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-10}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_unprivileged="${var_unprivileged:-1}"
#var_arm64="${var_arm64:-no}" # unset = ask the user; set yes/no only when verified
var_testurl="${var_testurl:-https://github.com/community-scripts/DevScripts/issues/2687}"

export var_authorized_key="${var_authorized_key:-}"
export var_gh_token="${var_gh_token:-}"

header_info "$APP"
variables
color
catch_errors

if [[ -n "${var_projects_mode:-}${var_projects_path:-}${var_projects_storage:-}${var_projects_size:-}" ]]; then
  msg_error "Projects storage options were removed; projects always live in /root/projects. Add an mp0 bind mount from the Proxmox UI if you need a host directory."
  exit 1
fi

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if ! command -v gentle-shell &>/dev/null; then
    msg_error "No ${APP} Installation Found!"
    exit 1
  fi

  RELEASE=$(npm view gentle-pi version 2>/dev/null)
  if [[ -z "${RELEASE}" ]]; then
    msg_error "Unable to reach npm for the latest gentle-pi version."
    exit 1
  fi
  msg_info "Updating ${APP} (gentle-pi@${RELEASE})"
  $STD npm install -g "gentle-pi@${RELEASE}"
  msg_ok "Updated ${APP}"
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW}Run 'gentle-shell' from the Proxmox console; for SSH or Herdr access, add a public key inside the container first.${CL}"
