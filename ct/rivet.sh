#!/usr/bin/env bash
_CS_DEFAULT_URL="https://raw.githubusercontent.com/community-scripts/DevScripts/main"
_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../core}/core/build.func"
source "$_cs_boot" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/build.func")
# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://github.com/rivet-dev/rivet

APP="Rivet"
var_tags="${var_tags:-backend;actors;dev-tools}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-8}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"
var_testurl="${var_testurl:-https://github.com/community-scripts/DevScripts/issues/2617}"

export var_admin_token="${var_admin_token:-}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -x /opt/rivet/rivet-engine ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "rivet" "rivet-dev/rivet"; then
    msg_info "Downloading Rivet Engine ${CHECK_UPDATE_RELEASE#v}"
    curl_with_retry "https://releases.rivet.dev/rivet/${CHECK_UPDATE_RELEASE#v}/engine/rivet-engine-$(arch_resolve "x86_64" "aarch64")-unknown-linux-musl" /opt/rivet/rivet-engine.new
    chmod +x /opt/rivet/rivet-engine.new
    msg_ok "Downloaded Rivet Engine ${CHECK_UPDATE_RELEASE#v}"

    msg_info "Stopping Rivet Engine"
    systemctl stop rivet
    msg_ok "Stopped Rivet Engine"

    mv /opt/rivet/rivet-engine.new /opt/rivet/rivet-engine
    cat <<EOF >~/.rivet
${CHECK_UPDATE_RELEASE#v}
EOF

    msg_info "Starting Rivet Engine"
    systemctl start rivet
    msg_ok "Started Rivet Engine"
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
echo -e "${GATEWAY}${BGN}http://${IP}:6420${CL}"
echo -e "${INFO}${YW}Admin token: auth.admin_token in /opt/rivet_data/config.json (inside the container)${CL}"
