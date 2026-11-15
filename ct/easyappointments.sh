#!/usr/bin/env bash
_CS_DEFAULT_URL="https://raw.githubusercontent.com/community-scripts/DevScripts/main"
_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../core}/core/build.func"
source "$_cs_boot" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/build.func")
# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://github.com/alextselegidis/easyappointments

APP="EasyAppointments"
var_tags="${var_tags:-scheduling;booking}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"
var_testurl="${var_testurl:-https://github.com/community-scripts/DevScripts/issues/2600}"

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

  if [[ ! -d /opt/easyappointments ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "easyappointments" "alextselegidis/easyappointments"; then
    msg_info "Stopping Easy!Appointments"
    systemctl stop nginx php8.4-fpm
    msg_ok "Stopped Easy!Appointments"

    create_backup /opt/easyappointments/application/config/email.php
    CLEAN_INSTALL=1 CLEAN_INSTALL_KEEP="config.php storage" fetch_and_deploy_gh_release "easyappointments" "alextselegidis/easyappointments" "prebuild" "latest" "/opt/easyappointments" "easyappointments-*.zip"
    restore_backup

    msg_info "Migrating Easy!Appointments Database"
    cd /opt/easyappointments
    $STD php index.php console migrate
    chown -R www-data:www-data /opt/easyappointments
    msg_ok "Migrated Easy!Appointments Database"

    msg_info "Starting Easy!Appointments"
    systemctl start php8.4-fpm nginx
    msg_ok "Started Easy!Appointments"
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
echo -e "${INFO}${YW}Admin login: /opt/easyappointments_data/.env (inside the container)${CL}"
