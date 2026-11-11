#!/usr/bin/env bash
_CS_DEFAULT_URL="https://raw.githubusercontent.com/community-scripts/DevScripts/main"
_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../core}/core/build.func"
source "$_cs_boot" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/build.func")

# Copyright (c) 2021-2026 community-scripts ORG
# Author: freakms
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://www.xwiki.org

APP="XWiki"
var_tags="${var_tags:-wiki}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-16}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_unprivileged="${var_unprivileged:-1}"
var_arm64="${var_arm64:-no}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -f /etc/xwiki/xwiki.cfg ]]; then
    msg_error "No XWiki Installation Found!"
    exit
  fi

  msg_info "Stopping XWiki"
  systemctl stop tomcat10
  msg_ok "Stopped XWiki"

  create_backup /etc/xwiki

  msg_info "Updating XWiki"
  apt_update_safe
  $STD apt install -y --only-upgrade -o Dpkg::Options::=--force-confold \
    xwiki-common xwiki-pgsql-common xwiki-tomcat10-common xwiki-tomcat10-pgsql
  msg_ok "Updated XWiki"

  restore_backup

  msg_info "Starting XWiki"
  systemctl start tomcat10
  msg_ok "Started XWiki"
  msg_ok "Updated successfully!"
  exit
}

start
build_container
description

msg_ok "Completed successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:8080/xwiki${CL}"
