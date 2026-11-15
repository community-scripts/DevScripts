#!/usr/bin/env bash
_CS_DEFAULT_URL="https://raw.githubusercontent.com/community-scripts/DevScripts/main"
_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../core}/core/build.func"
source "$_cs_boot" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/build.func")
# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://github.com/chibisafe/chibisafe

APP="Chibisafe"
var_tags="${var_tags:-files;sharing;upload}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-3072}"
var_disk="${var_disk:-8}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

export var_admin_pass="${var_admin_pass:-}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/chibisafe ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "chibisafe" "chibisafe/chibisafe"; then
    msg_info "Stopping Chibisafe"
    systemctl stop chibisafe-frontend chibisafe-backend
    msg_ok "Stopped Chibisafe"

    NODE_VERSION="26" setup_nodejs
    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "chibisafe" "chibisafe/chibisafe" "tarball"

    msg_info "Building Chibisafe"
    cd /opt/chibisafe
    $STD yarn workspaces focus @chibisafe/next
    NEXT_TELEMETRY_DISABLED=1 $STD yarn workspace @chibisafe/next build
    cp -r packages/next/public packages/next/.next/standalone/packages/next/
    cp -r packages/next/.next/static packages/next/.next/standalone/packages/next/.next/
    $STD yarn workspaces focus @chibisafe/backend
    $STD yarn workspace @chibisafe/backend generate
    $STD yarn workspace @chibisafe/backend build
    rm -rf packages/next/.next/cache
    $STD yarn cache clean --all
    ln -sfn /opt/chibisafe_data/database /opt/chibisafe/database
    ln -sfn /opt/chibisafe_data/uploads /opt/chibisafe/uploads
    ln -sfn /opt/chibisafe_data/logs /opt/chibisafe/logs
    msg_ok "Built Chibisafe"

    msg_info "Starting Chibisafe"
    systemctl start chibisafe-backend chibisafe-frontend
    msg_ok "Started Chibisafe"
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
echo -e "${GATEWAY}${BGN}http://${IP}${CL}"
echo -e "${INFO}${YW}Admin password (user admin): /opt/chibisafe_data/.env${CL}"
