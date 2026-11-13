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

  apt_update_safe
  if ! apt list --upgradable 2>/dev/null | grep -q '^xwiki-'; then
    msg_ok "XWiki is already up to date"
    exit 0
  fi

  echo
  msg_warn "The package update may include config file changes."
  echo -e "${TAB}${YW}How do you want to handle /etc/xwiki?${CL}"
  echo -e "${TAB}  1) Keep your current config"
  echo -e "${TAB}  2) Install the new package maintainer's config"
  if [[ "${PHS_SILENT:-0}" == "1" ]]; then
    CONFIG_CHOICE="1"
  else
    read -rp "  Choose [1/2] (default: 1): " -t 60 CONFIG_CHOICE || CONFIG_CHOICE="1"
  fi
  [[ -z "$CONFIG_CHOICE" ]] && CONFIG_CHOICE="1"

  msg_info "Stopping XWiki"
  systemctl stop tomcat10
  msg_ok "Stopped XWiki"

  if [[ "$CONFIG_CHOICE" == "2" ]]; then
    BACKUP_DIR="/opt/xwiki_config_$(date +%Y%m%d%H%M)" create_backup /etc/xwiki
    DPKG_CONF_OPT="--force-confnew"
  else
    create_backup /etc/xwiki
    DPKG_CONF_OPT="--force-confold"
  fi

  msg_info "Updating XWiki"
  $STD apt install -y --only-upgrade -o Dpkg::Options::="$DPKG_CONF_OPT" \
    xwiki-common xwiki-pgsql-common xwiki-tomcat10-common xwiki-tomcat10-pgsql
  msg_ok "Updated XWiki"

  if [[ "$CONFIG_CHOICE" == "2" ]]; then
    msg_warn "New package config installed. Your previous config is in /opt/xwiki_config_*/files/etc/xwiki"
  else
    restore_backup
  fi

  msg_info "Starting XWiki"
  systemctl start tomcat10
  msg_ok "Started XWiki"
  msg_ok "Updated successfully!"
  exit 0
}

start
build_container
description

msg_ok "Completed successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:8080/xwiki${CL}"
