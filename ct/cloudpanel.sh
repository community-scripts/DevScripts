#!/usr/bin/env bash
_CS_DEFAULT_URL="https://raw.githubusercontent.com/community-scripts/DevScripts/main"
_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../core}/core/build.func"
source "$_cs_boot" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/build.func")

# Copyright (c) 2021-2026 community-scripts ORG
# Author: TaiKamilla
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://www.cloudpanel.io/

APP="CloudPanel"
var_tags="${var_tags:-webserver;hosting;php}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-20}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

export var_db_engine="${var_db_engine:-}"
export var_admin_user="${var_admin_user:-}"
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

  if [[ ! -f /home/clp/htdocs/app/data/db.sq3 ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  $STD apt update
  if [[ -z "$(apt list --upgradable 2>/dev/null | grep '/')" ]]; then
    msg_ok "No update required. ${APP} is already up to date"
    exit
  fi

  msg_info "Updating CloudPanel"
  $STD clp-update
  $STD apt -y --with-new-pkgs --allow-downgrades upgrade
  msg_ok "Updated CloudPanel"
  msg_ok "Updated successfully!"
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW}Access it using the following URL:${CL}"
echo -e "${GATEWAY}${BGN}https://${IP}:8443${CL}"
echo -e "${INFO}${YW}Admin credentials: ~/cloudpanel.creds (inside the container)${CL}"
