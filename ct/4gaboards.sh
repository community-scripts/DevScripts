#!/usr/bin/env bash
_CS_DEFAULT_URL="https://raw.githubusercontent.com/community-scripts/DevScripts/main"
_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../core}/core/build.func"
source "$_cs_boot" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/build.func")
# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://github.com/RARgames/4gaBoards

APP="4ga Boards"
var_tags="${var_tags:-kanban;project-management}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-3072}"
var_disk="${var_disk:-8}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"
var_testurl="${var_testurl:-https://github.com/community-scripts/DevScripts/issues/2359}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/4gaboards ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "4gaboards" "RARgames/4gaBoards"; then
    msg_info "Stopping 4ga Boards"
    systemctl stop 4gaboards
    msg_ok "Stopped 4ga Boards"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "4gaboards" "RARgames/4gaBoards" "tarball"
    NODE_VERSION="24" NODE_MODULE="pnpm@$(jq -r '.engines.pnpm' /opt/4gaboards/package.json)" setup_nodejs

    msg_info "Building 4ga Boards"
    cd /opt/4gaboards
    $STD pnpm install --frozen-lockfile --filter "client..." --filter "server..."
    $STD pnpm packages:build
    DISABLE_ESLINT_PLUGIN=true $STD pnpm client:build
    cp -r client/build/. server/public/
    cp client/build/index.html server/views/index.ejs
    rm -rf server/private/attachments server/public/user-avatars server/public/project-background-images
    ln -s /opt/4gaboards_data/attachments server/private/attachments
    ln -s /opt/4gaboards_data/user-avatars server/public/user-avatars
    ln -s /opt/4gaboards_data/project-background-images server/public/project-background-images
    ln -s /opt/4gaboards_data/.env server/.env
    msg_ok "Built 4ga Boards"

    msg_info "Migrating 4ga Boards Database"
    cd /opt/4gaboards/server
    $STD node db/init.js
    msg_ok "Migrated 4ga Boards Database"

    msg_info "Starting 4ga Boards"
    systemctl start 4gaboards
    msg_ok "Started 4ga Boards"
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
echo -e "${GATEWAY}${BGN}http://${IP}:1337${CL}"
