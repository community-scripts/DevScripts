#!/usr/bin/env bash
_CS_DEFAULT_URL="https://raw.githubusercontent.com/community-scripts/DevScripts/main"
_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../core}/core/build.func"
source "$_cs_boot" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/build.func")
# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://github.com/mage-ai/mage-ai

APP="Mage"
var_tags="${var_tags:-etl;data;pipeline}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-8}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-no}" # mage-ai pins psutil 5.9.8, which has no aarch64 wheel and needs a C compiler there
var_unprivileged="${var_unprivileged:-1}"
var_testurl="${var_testurl:-https://github.com/community-scripts/DevScripts/issues/2616}"

export var_mage_password="${var_mage_password:-}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/mage-ai ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "mage-ai" "mage-ai/mage-ai"; then
    msg_info "Stopping Mage"
    systemctl stop mage-ai
    msg_ok "Stopped Mage"

    PYTHON_VERSION="3.12" setup_uv

    msg_info "Updating Mage to ${CHECK_UPDATE_RELEASE}"
    $STD uv pip install --upgrade --python /opt/mage-ai/.venv/bin/python "mage-ai==${CHECK_UPDATE_RELEASE}"
    cat <<EOF >~/.mage-ai
${CHECK_UPDATE_RELEASE}
EOF
    msg_ok "Updated Mage to ${CHECK_UPDATE_RELEASE}"

    msg_info "Starting Mage"
    systemctl start mage-ai
    msg_ok "Started Mage"
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
echo -e "${GATEWAY}${BGN}http://${IP}:6789${CL}"
echo -e "${INFO}${YW}Login: admin@admin.com, password DEFAULT_OWNER_PASSWORD in /opt/mage-ai_data/.env${CL}"
