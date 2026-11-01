#!/usr/bin/env bash
_CS_DEFAULT_URL="https://raw.githubusercontent.com/community-scripts/DevScripts/main"
_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../core}/core/build.func"
source "$_cs_boot" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/build.func")

# Copyright (c) 2021-2026 community-scripts ORG
# Author: andy-vdg
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://agentgateway.dev/

APP="agentgateway"
var_tags="${var_tags:-ai;proxy;mcp}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-512}"
var_disk="${var_disk:-2}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -f /etc/agentgateway/config.yaml ]]; then
    msg_error "No agentgateway Installation Found!"
    exit
  fi

  if check_for_gh_release "agentgateway" "agentgateway/agentgateway"; then
    msg_info "Stopping Service"
    systemctl stop agentgateway
    msg_ok "Stopped Service"

    create_backup /etc/agentgateway /opt/agentgateway_data

    fetch_and_deploy_gh_release "agentgateway" "agentgateway/agentgateway" "singlefile" "latest" "/opt/agentgateway" "agentgateway-linux-$(arch_resolve "amd64" "arm64")"

    restore_backup

    msg_info "Verifying agentgateway Checksum"
    AGW_SUM=$(curl -fsSL "https://github.com/agentgateway/agentgateway/releases/download/v$(cat ~/.agentgateway)/agentgateway-linux-$(arch_resolve "amd64" "arm64").sha256" | awk '{print $1}') || AGW_SUM=""
    echo "${AGW_SUM}  /opt/agentgateway/agentgateway" | sha256sum -c --status || { rm -f /opt/agentgateway/agentgateway ~/.agentgateway; msg_error "agentgateway checksum missing or wrong - removed the downloaded binary"; exit 1; }
    chmod +x /opt/agentgateway/agentgateway
    msg_ok "Verified agentgateway Checksum"

    msg_info "Starting Service"
    systemctl start agentgateway
    msg_ok "Started Service"
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
echo -e "${GATEWAY}${BGN}http://${IP}:4000/ui${CL}"
