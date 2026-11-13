#!/usr/bin/env bash
_CS_DEFAULT_URL="https://raw.githubusercontent.com/community-scripts/DevScripts/main"
_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../core}/core/build.func"
source "$_cs_boot" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/build.func")
# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://github.com/nocobase/nocobase

APP="NocoBase"
var_tags="${var_tags:-no-code;low-code;database}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-8}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"
var_testurl="${var_testurl:-https://github.com/community-scripts/DevScripts/issues/2623}"

export var_admin_email="${var_admin_email:-}"
export var_admin_pass="${var_admin_pass:-}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -f /opt/nocobase/node_modules/@nocobase/app/package.json ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  CURRENT=$(node -p "require('/opt/nocobase/node_modules/@nocobase/app/package.json').version")
  RELEASE=$(npm view @nocobase/app version 2>/dev/null)
  if [[ -z "$RELEASE" ]]; then
    msg_error "Could not determine the latest NocoBase version from npm"
    exit 1
  fi
  if [[ "$RELEASE" == "$CURRENT" ]]; then
    msg_ok "No update available: NocoBase (${CURRENT})"
    exit
  fi

  NODE_VERSION="22" NODE_MODULE="yarn" setup_nodejs

  msg_info "Stopping NocoBase"
  systemctl stop nocobase
  msg_ok "Stopped NocoBase"

  msg_info "Updating NocoBase from ${CURRENT} to ${RELEASE}"
  cd /opt/nocobase
  $STD npm pkg set "dependencies.@nocobase/app=${RELEASE}"
  $STD yarn install --production
  $STD yarn nocobase upgrade --skip-code-update
  $STD yarn cache clean
  msg_ok "Updated NocoBase from ${CURRENT} to ${RELEASE}"

  msg_info "Starting NocoBase"
  systemctl start nocobase
  msg_ok "Started NocoBase"
  msg_ok "Updated successfully!"
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW}Access it using the following URL:${CL}"
echo -e "${GATEWAY}${BGN}http://${IP}:13000${CL}"
echo -e "${INFO}${YW}Root login: /opt/nocobase_data/.env (inside the container)${CL}"
