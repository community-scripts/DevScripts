#!/usr/bin/env bash
_CS_DEFAULT_URL="https://raw.githubusercontent.com/community-scripts/DevScripts/main"
_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../core}/core/build.func"
source "$_cs_boot" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/build.func")

# Copyright (c) 2021-2026 community-scripts ORG
# Author: clartek
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://meshmonitor.org/

APP="MeshMonitor"
var_tags="${var_tags:-meshtastic;meshcore;monitoring}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-10}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
#var_arm64="${var_arm64:-no}" # Native dependencies have not been tested on arm64.
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/meshmonitor ]]; then
    msg_error "No MeshMonitor Installation Found!"
    exit 1
  fi

  if check_for_gh_release "meshmonitor" "Yeraze/meshmonitor"; then
    msg_info "Stopping MeshMonitor"
    systemctl stop meshmonitor meshmonitor-apprise
    msg_ok "Stopped MeshMonitor"

    create_backup /data /etc/meshmonitor

    NODE_VERSION="24" setup_nodejs
    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "meshmonitor" "Yeraze/meshmonitor" "tarball"
    restore_backup

    # GitHub source archives omit submodules; use the commits pinned by this release.
    github_api_call "https://api.github.com/repos/Yeraze/meshmonitor/git/trees/v$(cat ~/.meshmonitor)" /tmp/meshmonitor-tree.json
    protobuf_commit=$(jq -er '.tree[] | select(.path == "protobufs" and .type == "commit") | .sha' /tmp/meshmonitor-tree.json)
    takpacket_commit=$(jq -er '.tree[] | select(.path == "takpacket-sdk" and .type == "commit") | .sha' /tmp/meshmonitor-tree.json)
    fetch_and_deploy_from_url "https://github.com/meshtastic/protobufs/archive/${protobuf_commit}.tar.gz" /opt/meshmonitor/protobufs
    fetch_and_deploy_from_url "https://github.com/meshtastic/TAKPacket-SDK/archive/${takpacket_commit}.tar.gz" /opt/meshmonitor/takpacket-sdk
    rm -f /tmp/meshmonitor-tree.json

    msg_info "Building MeshMonitor"
    cd /opt/meshmonitor || exit 1
    PUPPETEER_SKIP_DOWNLOAD=true $STD npm install --legacy-peer-deps
    $STD npm run build
    $STD npm run build:server
    $STD npm prune --omit=dev --legacy-peer-deps
    msg_ok "Built MeshMonitor"

    msg_info "Updating MeshMonitor Python Dependencies"
    $STD uv pip install --upgrade --python /opt/meshmonitor-venv/bin/python apprise requests "paho-mqtt<2.0" meshtastic meshcore-cli
    msg_ok "Updated MeshMonitor Python Dependencies"

    msg_info "Starting MeshMonitor"
    systemctl start meshmonitor-apprise meshmonitor
    msg_ok "Started MeshMonitor"
    msg_ok "Updated MeshMonitor successfully!"
  fi
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}MeshMonitor setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW}Access it using the following URL:${CL}"
echo -e "${GATEWAY}${BGN}http://${IP}:3001${CL}"
echo -e "${INFO}${YW}Log in as admin with password changeme, change the password, then add your node in the web UI.${CL}"
