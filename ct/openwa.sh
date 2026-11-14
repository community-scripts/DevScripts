#!/usr/bin/env bash
_CS_DEFAULT_URL="https://raw.githubusercontent.com/community-scripts/DevScripts/main"
_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../core}/core/build.func"
source "$_cs_boot" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/build.func")
# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://github.com/rmyndharis/OpenWA

APP="OpenWA"
var_tags="${var_tags:-whatsapp;messaging;api}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-6}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
#var_arm64="${var_arm64:-no}" # unset = ask the user; set yes/no only when verified
var_unprivileged="${var_unprivileged:-1}"
var_testurl="${var_testurl:-https://github.com/community-scripts/DevScripts/issues/2643}"

export var_api_key="${var_api_key:-}"

header_info "$APP"
variables
color
catch_errors

if [[ -n "$var_api_key" && ${#var_api_key} -lt 32 ]]; then
  msg_error "var_api_key must be at least 32 characters long."
  exit 1
fi

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/openwa ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "openwa" "rmyndharis/OpenWA"; then
    msg_info "Stopping OpenWA"
    systemctl stop openwa
    msg_ok "Stopped OpenWA"

    NODE_VERSION="22" setup_nodejs
    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "openwa" "rmyndharis/OpenWA" "tarball"

    msg_info "Building OpenWA"
    cd /opt/openwa
    export PUPPETEER_SKIP_DOWNLOAD=true
    $STD npm ci
    $STD npm run build
    $STD npm run dashboard:build
    $STD npm prune --omit=dev
    rm -rf dashboard/node_modules ~/.npm
    msg_ok "Built OpenWA"

    msg_info "Starting OpenWA"
    systemctl start openwa
    msg_ok "Started OpenWA"
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
echo -e "${GATEWAY}${BGN}http://${IP}:2785${CL}"
echo -e "${INFO}${YW}Admin API key: API_MASTER_KEY in /opt/openwa_data/.env${CL}"
