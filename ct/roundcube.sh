#!/usr/bin/env bash
_CS_DEFAULT_URL="https://raw.githubusercontent.com/community-scripts/DevScripts/main"
_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../core}/core/build.func"
source "$_cs_boot" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/build.func")
# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://github.com/roundcube/roundcubemail

APP="Roundcube"
var_tags="${var_tags:-mail;webmail}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-512}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

export var_imap_host="${var_imap_host:-}"
export var_smtp_host="${var_smtp_host:-}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/roundcube ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "roundcube" "roundcube/roundcubemail"; then
    msg_info "Stopping Roundcube"
    systemctl stop nginx
    msg_ok "Stopped Roundcube"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "roundcube" "roundcube/roundcubemail" "prebuild" "latest" "/opt/roundcube_update" "roundcubemail-*-complete.tar.gz"

    msg_info "Updating Roundcube"
    $STD php /opt/roundcube_update/bin/installto.sh -y /opt/roundcube
    rm -rf /opt/roundcube_update
    chown -R www-data:www-data /opt/roundcube /opt/roundcube_data
    msg_ok "Updated Roundcube"

    msg_info "Starting Roundcube"
    systemctl start nginx
    msg_ok "Started Roundcube"
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
