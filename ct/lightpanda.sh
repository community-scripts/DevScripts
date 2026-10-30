#!/usr/bin/env bash
_CS_DEFAULT_URL="https://raw.githubusercontent.com/community-scripts/DevScripts/main"
_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../core}/core/build.func"
source "$_cs_boot" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/build.func")

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Aditya Raj Singh (justadityaraj)
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://lightpanda.io/

APP="Lightpanda"
var_tags="${var_tags:-browser;automation;ai}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_unprivileged="${var_unprivileged:-1}"
var_arm64="${var_arm64:-yes}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -f /usr/bin/lightpanda ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "lightpanda" "lightpanda-io/browser"; then
    msg_info "Stopping Lightpanda"
    systemctl stop lightpanda lightpanda-mcp
    msg_ok "Stopped Lightpanda"

    fetch_and_deploy_gh_release "lightpanda" "lightpanda-io/browser" "binary"

    msg_info "Starting Lightpanda"
    systemctl start lightpanda lightpanda-mcp
    msg_ok "Started Lightpanda"
    msg_ok "Updated successfully!"
  fi
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
