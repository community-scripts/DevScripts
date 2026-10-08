#!/usr/bin/env bash
_CS_DEFAULT_URL="https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main"
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
var_arm64="${var_arm64:-no}" # not verified on Proxmox aarch64 (upstream publishes linux-arm64.tar.xz)
var_unprivileged="${var_unprivileged:-1}"

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
    grep -oE 'v5/dist/tinyMediaManager-[0-9.]+-linux-amd64\.tar\.xz' |
    head -1)
  if [[ -z "${ASSET_PATH}" ]]; then
    msg_error "Could not resolve the official Linux amd64 download URL."
    exit 1
  fi
  ASSET_URL="https://release.tinymediamanager.org/${ASSET_PATH}"
  VERSION=$(basename "${ASSET_PATH}" | grep -oE '[0-9]+(\.[0-9]+)+')
  CURRENT=$(cat ~/.tinymediamanager 2>/dev/null || true)

  if [[ -z "${VERSION}" ]]; then
    msg_error "Could not parse tinyMediaManager version from download URL."
    exit 1
  fi

  if [[ "${CURRENT}" == "${VERSION}" ]]; then
    msg_ok "tinyMediaManager is already up to date (${VERSION})"
    exit
  fi

  msg_info "Stopping tinyMediaManager"
  systemctl stop tinymediamanager x11vnc novnc
  msg_ok "Stopped tinyMediaManager"

  CLEAN_INSTALL=1 fetch_and_deploy_from_url "${ASSET_URL}" /opt/tinymediamanager
  if [[ ! -f /opt/tinymediamanager/tinyMediaManager ]]; then
    msg_error "tinyMediaManager binary not found after deploy."
    exit 1
  fi
  chmod +x /opt/tinymediamanager/tinyMediaManager
  cat <<EOF >/opt/tinymediamanager/launcher-extra.yml
javaHome: ""
jvmOpts:
  - "-Dtmm.contentfolder=/opt/tinymediamanager_data"
  - "-Dtmm.noupdate=true"
  - "-Dtmm.legacy.filechooser=true"
env:
  - "_JAVA_AWT_WM_NONREPARENTING=1"
EOF
  echo "${VERSION}" >~/.tinymediamanager

  msg_info "Starting tinyMediaManager"
  systemctl start tinymediamanager
  sleep 2
  systemctl start x11vnc novnc
  msg_ok "Started tinyMediaManager"
  msg_ok "Updated tinyMediaManager ${CURRENT:-unknown} -> ${VERSION}"
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW}Access it using the following URL:${CL}"
echo -e "${GATEWAY}${BGN}http://${IP}:6080/vnc.html?resize=scale&autoconnect=true${CL}"
