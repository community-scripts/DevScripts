#!/usr/bin/env bash
_CS_DEFAULT_URL="https://raw.githubusercontent.com/community-scripts/DevScripts/main"
_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../core}/core/build.func"
source "$_cs_boot" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/build.func")

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Estcool9
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://github.com/heygen-com/hyperframes

APP="HyperFrames CLI"
var_tags="${var_tags:-development;video;editing;ai}"
var_cpu="${var_cpu:-4}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-20}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_unprivileged="${var_unprivileged:-1}"
var_arm64="${var_arm64:-yes}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if ! command -v hyperframes >/dev/null 2>&1; then
    msg_error "No HyperFrames installation found!"
    exit
  fi

  NODE_VERSION="22" NODE_MODULE="hyperframes" setup_nodejs
  setup_ffmpeg

  if [[ "$(dpkg --print-architecture)" == "arm64" ]]; then
    msg_info "Ensuring Chromium for ARM64"
    $STD apt install -y chromium
    msg_ok "Ensured Chromium for ARM64"
  fi

  $STD hyperframes browser ensure
  msg_ok "Updated successfully!"
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW}Use the CLI over SSH; projects are stored in /opt/hyperframes_data.${CL}"
