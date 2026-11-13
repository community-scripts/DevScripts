#!/usr/bin/env bash
_CS_DEFAULT_URL="https://raw.githubusercontent.com/community-scripts/DevScripts/main"
_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../core}/core/build.func"
source "$_cs_boot" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/build.func")
# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://github.com/evolution-foundation/evolution-api

APP="Evolution API"
var_tags="${var_tags:-whatsapp;messaging;api}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-8}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
#var_arm64="${var_arm64:-no}" # unset = ask the user; set yes/no only when verified
var_unprivileged="${var_unprivileged:-1}"

export var_api_key="${var_api_key:-}"
export var_server_url="${var_server_url:-}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/evolution-api ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "evolution-api" "evolution-foundation/evolution-api"; then
    msg_info "Stopping Evolution API"
    systemctl stop evolution-api
    msg_ok "Stopped Evolution API"

    NODE_VERSION="24" setup_nodejs
    CLEAN_INSTALL=1 CLEAN_INSTALL_KEEP=".env instances store" fetch_and_deploy_gh_release "evolution-api" "evolution-foundation/evolution-api" "tarball"

    msg_info "Building Evolution API"
    cd /opt/evolution-api
    $STD npm ci
    $STD npm run db:generate
    $STD npm run build
    $STD npm run db:deploy
    $STD npm prune --omit=dev
    rm -rf ~/.npm
    msg_ok "Built Evolution API"

    msg_info "Starting Evolution API"
    systemctl start evolution-api
    msg_ok "Started Evolution API"
    msg_ok "Updated successfully!"
  fi
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW}Access the manager using the following URL:${CL}"
echo -e "${GATEWAY}${BGN}http://${IP}:8080/manager${CL}"
echo -e "${INFO}${YW}Global API key: AUTHENTICATION_API_KEY in /opt/evolution-api_data/.env${CL}"
