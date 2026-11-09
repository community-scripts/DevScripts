#!/usr/bin/env bash
_CS_DEFAULT_URL="https://raw.githubusercontent.com/community-scripts/DevScripts/main"
_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../core}/core/build.func"
source "$_cs_boot" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/build.func")
# Copyright (c) 2021-2026 community-scripts ORG
# Author: Valentin Levshits (vlevshits)
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://github.com/vlevshits/genealogy

APP="Genealogy"
var_tags="${var_tags:-genealogy;family-tree}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-8}"
var_os="${var_os:-debian}"
var_version="${var_version:-12}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -f /etc/systemd/system/genealogy.service ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  msg_info "Updating ${APP}"
  if [[ -x /usr/local/bin/update ]]; then
    /usr/local/bin/update
  elif [[ -f /opt/genealogy/scripts/install.sh ]]; then
    /opt/genealogy/scripts/install.sh
  else
    curl -fsSL https://raw.githubusercontent.com/vlevshits/genealogy/main/scripts/install.sh | bash
  fi
  msg_ok "Updated ${APP}"
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully completed!${CL}"
echo -e "${INFO}${YW} Access it at: ${BL}http://${IP}:80${CL}"
