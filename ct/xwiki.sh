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
# amd64 only: the XWiki Debian packages are architecture independent, but
# they are not tested on arm64 yet.
var_arm64="${var_arm64:-no}"

# Read by install/xwiki-install.sh
export var_xwiki_db="${var_xwiki_db:-pgsql}"
export var_xwiki_channel="${var_xwiki_channel:-stable}"
export var_xwiki_xmx="${var_xwiki_xmx:-}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -f /etc/xwiki/xwiki.cfg ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  msg_info "Stopping ${APP}"
  systemctl stop tomcat10
  msg_ok "Stopped ${APP}"

  msg_info "Backing up ${APP} configuration"
  mkdir -p /opt/xwiki_backup
  cp -a /etc/xwiki "/opt/xwiki_backup/etc-xwiki-$(date +%F)"
  msg_ok "Backed up ${APP} configuration"

  msg_info "Updating ${APP}"
  export DEBIAN_FRONTEND=noninteractive
  mapfile -t XWIKI_PKGS < <(dpkg-query -W -f='${db:Status-Abbrev} ${Package}\n' 'xwiki-*' 2>/dev/null | awk '$1 == "ii" {print $2}')
  $STD apt update
  $STD apt install -y --only-upgrade -o Dpkg::Options::=--force-confold "${XWIKI_PKGS[@]}"
  msg_ok "Updated ${APP}"

  msg_info "Starting ${APP}"
  systemctl start tomcat10
  msg_ok "Started ${APP}"
  msg_ok "Updated successfully! After a major upgrade, open ${APP} in the browser and finish the Distribution Wizard."
  exit
}

start
build_container
description

msg_ok "Completed successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:8080/xwiki${CL}"
