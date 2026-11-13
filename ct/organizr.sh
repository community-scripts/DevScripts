#!/usr/bin/env bash
_CS_DEFAULT_URL="https://raw.githubusercontent.com/community-scripts/DevScripts/main"
_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../core}/core/build.func"
source "$_cs_boot" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/build.func")
# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://github.com/causefx/Organizr

APP="Organizr"
var_tags="${var_tags:-dashboard;sso}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-512}"
var_disk="${var_disk:-3}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

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

  if [[ ! -d /opt/organizr ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_branch "organizr" "causefx/Organizr" "v2-master"; then
    msg_info "Stopping Organizr"
    systemctl stop nginx php8.4-fpm
    msg_ok "Stopped Organizr"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_branch "organizr" "causefx/Organizr" "v2-master"

    msg_info "Configuring Organizr"
    ln -sfn /opt/organizr_data/data /opt/organizr/data
    chown -R www-data:www-data /opt/organizr
    msg_ok "Configured Organizr"

    msg_info "Starting Organizr"
    systemctl start php8.4-fpm nginx
    msg_ok "Started Organizr"
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
echo -e "${INFO}${YW}Admin credentials: /opt/organizr_data/.env (inside the container)${CL}"
