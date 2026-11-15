#!/usr/bin/env bash
_CS_DEFAULT_URL="https://raw.githubusercontent.com/community-scripts/DevScripts/main"
_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../core}/core/build.func"
source "$_cs_boot" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/build.func")
# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://github.com/zulip/zulip

APP="Zulip"
var_tags="${var_tags:-chat;communication}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-12}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
#var_arm64="${var_arm64:-no}" # unset = ask the user; set yes/no only when verified
var_unprivileged="${var_unprivileged:-1}"
var_testurl="${var_testurl:-https://github.com/community-scripts/DevScripts/issues/2562}"

export var_zulip_hostname="${var_zulip_hostname:-}"
export var_zulip_email="${var_zulip_email:-}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /home/zulip/deployments/current ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "zulip" "zulip/zulip"; then
    USE_ORIGINAL_FILENAME=true fetch_and_deploy_gh_release "zulip" "zulip/zulip" "singlefile" "latest" "/opt/zulip" "zulip-server-*.tar.gz"

    msg_info "Stopping Zulip"
    $STD /home/zulip/deployments/current/scripts/stop-server
    msg_ok "Stopped Zulip"

    msg_info "Updating Zulip"
    $STD /home/zulip/deployments/current/scripts/upgrade-zulip "/opt/zulip/zulip-server-$(cat ~/.zulip).tar.gz"
    rm -rf /opt/zulip
    msg_ok "Updated Zulip"
    msg_ok "Updated successfully!"
  fi
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW}Access it using the following URL:${CL}"
echo -e "${GATEWAY}${BGN}https://${var_zulip_hostname:-${IP}}${CL}"
echo -e "${INFO}${YW}Organization creation link: ~/zulip.creds (inside the container)${CL}"
