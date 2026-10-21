#!/usr/bin/env bash
_CS_DEFAULT_URL="https://raw.githubusercontent.com/community-scripts/DevScripts/main"
_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../core}/core/build.func"
source "$_cs_boot" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/build.func")
# Copyright (c) 2021-2026 community-scripts ORG
# Author: Shrijayan
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://github.com/bemmoly/bemmoly

APP="Bemmoly"
var_tags="${var_tags:-project-management;wiki}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-10}"
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

  if [[ ! -d /opt/bemmoly ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "bemmoly" "bemmoly/bemmoly"; then
    msg_info "Stopping Bemmoly"
    systemctl stop bemmoly
    msg_ok "Stopped Bemmoly"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "bemmoly" "bemmoly/bemmoly" "tarball"
    NODE_VERSION="24" NODE_MODULE="$(jq -r '.packageManager' /opt/bemmoly/package.json)" setup_nodejs

    msg_info "Building Bemmoly"
    cd /opt/bemmoly
    $STD pnpm install --frozen-lockfile
    $STD pnpm --filter @bemmoly/web build
    msg_ok "Built Bemmoly"

    msg_info "Migrating Bemmoly Database"
    cd /opt/bemmoly/apps/server
    $STD node --env-file=/opt/bemmoly_data/.env src/cli.ts db update
    msg_ok "Migrated Bemmoly Database"

    msg_info "Starting Bemmoly"
    systemctl start bemmoly
    msg_ok "Started Bemmoly"
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
echo -e "${GATEWAY}${BGN}http://${IP}:8080${CL}"
