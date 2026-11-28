#!/usr/bin/env bash
_CS_DEFAULT_URL="https://raw.githubusercontent.com/community-scripts/DevScripts/main"
_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../core}/core/build.func"
source "$_cs_boot" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/build.func")

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Estcool9
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://github.com/debpalash/VoiceStudio

APP="VoiceStudio"
var_tags="${var_tags:-ai;audio;tts;voice-cloning}"
var_cpu="${var_cpu:-6}"
var_ram="${var_ram:-12288}"
var_disk="${var_disk:-50}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_unprivileged="${var_unprivileged:-1}"
#var_arm64="${var_arm64:-no}" # unset = ask the user; set yes/no only when verified
export var_voicestudio_hf_token="${var_voicestudio_hf_token:-}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/voicestudio || ! -f /opt/voicestudio_data/.env ]]; then
    msg_error "No VoiceStudio Installation Found!"
    exit 1
  fi

  if ! systemctl is-active --quiet voicestudio; then
    msg_warn "VoiceStudio is not running; skipping the automatic update."
    exit 0
  fi

  if ! curl -fsS --max-time 5 http://127.0.0.1:3900/jobs | jq -e 'length == 0' >/dev/null; then
    msg_warn "VoiceStudio has active jobs or its API is unavailable; skipping the update."
    exit 0
  fi

  if ! curl -fsS --max-time 5 http://127.0.0.1:3900/models/install/status | jq -e '.jobs | length == 0' >/dev/null; then
    msg_warn "A model download is active or its status cannot be checked; skipping the update."
    exit 0
  fi

  if check_for_gh_release "voicestudio" "debpalash/VoiceStudio"; then
    msg_info "Stopping VoiceStudio"
    systemctl stop voicestudio
    msg_ok "Stopped VoiceStudio"

    if ! (
      set -e
      mkdir -p /opt/voicestudio_data/uv/python
      export UV_PYTHON_INSTALL_DIR=/opt/voicestudio_data/uv/python
      CLEAN_INSTALL=1 fetch_and_deploy_gh_release "voicestudio" "debpalash/VoiceStudio" "tarball"
      PYTHON_VERSION="3.11" setup_uv
      NODE_VERSION="22" NODE_MODULE="$(jq -r '.packageManager' /opt/voicestudio/package.json)" setup_nodejs
      cd /opt/voicestudio
      $STD bun install --frozen-lockfile
      $STD bun run setup:api
      $STD bun run --cwd electron build:web
      rm -rf /opt/voicestudio/node_modules /opt/voicestudio/electron/node_modules
    ); then
      msg_error "VoiceStudio update failed; attempting to restart the service."
      systemctl start voicestudio || true
      exit 1
    fi

    msg_info "Starting VoiceStudio"
    systemctl start voicestudio
    if ! $STD curl --retry 60 --retry-delay 2 --retry-connrefused -fsS http://127.0.0.1:3900/health; then
      msg_error "VoiceStudio failed its health check after the update."
      exit 1
    fi
    msg_ok "Updated VoiceStudio successfully!"
  fi
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\\n"
echo -e "${CREATING}${GN}VoiceStudio setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW}Access it using the following URL:${CL}"
echo -e "${GATEWAY}${BGN}http://${IP}:3900${CL}"
