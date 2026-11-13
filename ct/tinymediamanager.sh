#!/usr/bin/env bash
_CS_DEFAULT_URL="https://raw.githubusercontent.com/community-scripts/DevScripts/main"
_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../core}/core/build.func"
source "$_cs_boot" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/build.func")
# Copyright (c) 2021-2026 community-scripts ORG
# Author: Borja Garduño (Borja-Garduno)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://www.tinymediamanager.org/

APP="tinyMediaManager"
var_tags="${var_tags:-media;library}"
var_cpu="${var_cpu:-4}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-12}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
#var_arm64="${var_arm64:-no}" # unset = ask the user; set yes/no only when verified
var_unprivileged="${var_unprivileged:-1}"
var_testurl="${var_testurl:-https://github.com/community-scripts/DevScripts/issues/2557}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -f /opt/tinymediamanager/tinyMediaManager ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  ASSET_PATH=$(curl -fsSL https://release.tinymediamanager.org/ |
    grep -oE "v5/dist/tinyMediaManager-[0-9.]+-linux-$(arch_resolve)\\.tar\\.xz" |
    head -1)
  ASSET_URL="https://release.tinymediamanager.org/${ASSET_PATH}"
  VERSION=$(basename "${ASSET_PATH}" | grep -oE '[0-9]+(\.[0-9]+)+')
  CURRENT=$(cat ~/.tinymediamanager 2>/dev/null || true)

  if [[ "${CURRENT}" == "${VERSION}" ]]; then
    msg_ok "tinyMediaManager is already up to date (${VERSION})"
    exit
  fi

  msg_info "Stopping tinyMediaManager"
  systemctl stop tinymediamanager x11vnc novnc
  msg_ok "Stopped tinyMediaManager"

  create_backup \
    /opt/tinymediamanager/data \
    /opt/tinymediamanager/backup \
    /opt/tinymediamanager/addons \
    /opt/tinymediamanager/launcher-extra.yml

  CLEAN_INSTALL=1 fetch_and_deploy_from_url "${ASSET_URL}" /opt/tinymediamanager
  restore_backup

  rm -f /opt/tinymediamanager/.userdir
  chmod +x /opt/tinymediamanager/tinyMediaManager
  echo "${VERSION}" >~/.tinymediamanager

  msg_info "Starting tinyMediaManager"
  systemctl start tinymediamanager
  sleep 2
  systemctl start x11vnc novnc
  msg_ok "Started tinyMediaManager"
  msg_ok "Updated tinyMediaManager ${CURRENT} -> ${VERSION}"
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW}Access it using the following URL:${CL}"
echo -e "${GATEWAY}${BGN}http://${IP}:6080/vnc.html or on port 5900 with a VNC client${CL}"
