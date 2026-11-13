#!/usr/bin/env bash
_CS_DEFAULT_URL="https://raw.githubusercontent.com/community-scripts/DevScripts/main"
_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../core}/core/build.func"
source "$_cs_boot" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/build.func")
# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://github.com/HumanSignal/label-studio

APP="Label-Studio"
var_tags="${var_tags:-ai;machine-learning;annotation}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-8}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

export var_admin_email="${var_admin_email:-}"
export var_admin_pass="${var_admin_pass:-}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/label-studio ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "label-studio" "HumanSignal/label-studio"; then
    msg_info "Stopping Label Studio"
    systemctl stop label-studio
    msg_ok "Stopped Label Studio"

    PYTHON_VERSION="3.13" setup_uv

    msg_info "Updating Label Studio"
    $STD uv pip install --upgrade --python /opt/label-studio/.venv/bin/python "label-studio==${CHECK_UPDATE_RELEASE}"
    cd /opt/label-studio_data
    set -a && source /opt/label-studio_data/.env && set +a
    $STD /opt/label-studio/.venv/bin/label-studio init -q
    cat <<EOF >~/.label-studio
${CHECK_UPDATE_RELEASE}
EOF
    msg_ok "Updated Label Studio"

    msg_info "Starting Label Studio"
    systemctl start label-studio
    msg_ok "Started Label Studio"
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
echo -e "${GATEWAY}${BGN}http://${IP}:8080${CL}"
echo -e "${INFO}${YW}Login: LABEL_STUDIO_USERNAME / LABEL_STUDIO_PASSWORD in /opt/label-studio_data/.env (inside the container)${CL}"
