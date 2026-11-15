#!/usr/bin/env bash
_CS_DEFAULT_URL="https://raw.githubusercontent.com/community-scripts/DevScripts/main"
_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../core}/core/build.func"
source "$_cs_boot" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/build.func")
# Copyright (c) 2021-2026 community-scripts ORG
# Author: Estcool9 (Estcool9)
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://github.com/debpalash/VoiceStudio

APP="VoiceStudio"
var_tags="${var_tags:-ai;audio;tts;voice}"
var_cpu="${var_cpu:-6}"
var_ram="${var_ram:-12288}"
var_disk="${var_disk:-50}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-no}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/voicestudio ]]; then
    msg_error "No VoiceStudio Installation Found!"
    exit
  fi

  if check_for_gh_release "voicestudio" "debpalash/VoiceStudio"; then
    msg_info "Stopping VoiceStudio"
    systemctl stop voicestudio
    msg_ok "Stopped VoiceStudio"

    NODE_VERSION="22" NODE_MODULE="bun@1.4.2" setup_nodejs
    PYTHON_VERSION="3.12" setup_uv
    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "voicestudio" "debpalash/VoiceStudio" "tarball"

    msg_info "Building VoiceStudio"
    cd /opt/voicestudio
    $STD bun install --frozen-lockfile
    OMNIVOICE_TORCH_VARIANT=cpu $STD bun run setup:api
    $STD bun run build:web
    msg_ok "Built VoiceStudio"

    msg_info "Starting VoiceStudio"
    systemctl start voicestudio
    msg_ok "Started VoiceStudio"
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
echo -e "${GATEWAY}${BGN}http://${IP}:3900${CL}"
echo -e "${INFO}${YW}API key: /opt/voicestudio_data/.env (OMNIVOICE_API_KEY). For first browser login, append #api_key=<key> to the URL.${CL}"
