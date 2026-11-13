#!/usr/bin/env bash
_CS_DEFAULT_URL="https://raw.githubusercontent.com/community-scripts/DevScripts/main"
_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../core}/core/build.func"
source "$_cs_boot" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/build.func")
# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://github.com/joomla/joomla-cms

APP="Joomla"
var_tags="${var_tags:-cms;website}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

export var_admin_user="${var_admin_user:-}"
export var_admin_pass="${var_admin_pass:-}"
export var_admin_email="${var_admin_email:-}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -f /opt/joomla/configuration.php ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  # Joomla also updates itself from the admin panel
  sed -n 's|.*<version>\(.*\)</version>.*|\1|p' /opt/joomla/administrator/manifests/files/joomla.xml >~/.joomla
  if check_for_gh_release "joomla" "joomla/joomla-cms" "" "" "$(cut -d. -f1 ~/.joomla)."; then
    msg_info "Updating Joomla"
    cd /opt/joomla
    $STD php cli/joomla.php core:update
    chown -R www-data:www-data /opt/joomla
    sed -n 's|.*<version>\(.*\)</version>.*|\1|p' /opt/joomla/administrator/manifests/files/joomla.xml >~/.joomla
    msg_ok "Updated Joomla"
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
echo -e "${GATEWAY}${BGN}http://${IP}/administrator${CL}"
echo -e "${INFO}${YW}Admin login: /opt/joomla_data/.env (inside the container)${CL}"
