#!/usr/bin/env bash
_CS_DEFAULT_URL="https://raw.githubusercontent.com/community-scripts/DevScripts/main"
_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../core}/core/build.func"
source "$_cs_boot" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/build.func")
# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://github.com/atuinsh/atuin

APP="Atuin"
var_tags="${var_tags:-shell;sync}"
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

  if [[ ! -d /opt/atuin ]]; then
    msg_error "No Atuin Installation Found!"
    exit
  fi

  if check_for_gh_release "atuin" "atuinsh/atuin"; then
    msg_info "Stopping Atuin Server"
    systemctl stop atuin-server
    msg_ok "Stopped Atuin Server"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "atuin" "atuinsh/atuin" "prebuild" "latest" "/opt/atuin" "atuin-server-$(arch_resolve "x86_64" "aarch64")-unknown-linux-gnu.tar.gz"

    msg_info "Starting Atuin Server"
    systemctl start atuin-server
    msg_ok "Started Atuin Server"
    msg_ok "Updated successfully!"
  fi
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}Atuin Server setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW}Point your Atuin clients at the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:8888${CL}"
