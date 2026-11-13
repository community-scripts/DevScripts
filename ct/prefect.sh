#!/usr/bin/env bash
_CS_DEFAULT_URL="https://raw.githubusercontent.com/community-scripts/DevScripts/main"
_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../core}/core/build.func"
source "$_cs_boot" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/build.func")
# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://github.com/PrefectHQ/prefect

APP="Prefect"
var_tags="${var_tags:-automation;workflow;python}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"
var_testurl="${var_testurl:-https://github.com/community-scripts/DevScripts/issues/2587}"

export var_prefect_user="${var_prefect_user:-}"
export var_prefect_password="${var_prefect_password:-}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/prefect ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "prefect-server" "PrefectHQ/prefect" "" "" "3."; then
    msg_info "Stopping Prefect"
    systemctl stop prefect-worker prefect-server
    msg_ok "Stopped Prefect"

    PYTHON_VERSION="3.12" setup_uv

    msg_info "Updating Prefect"
    $STD uv pip install --python /opt/prefect/.venv/bin/python "prefect==${CHECK_UPDATE_RELEASE}"
    cat <<EOF >~/.prefect-server
${CHECK_UPDATE_RELEASE}
EOF
    msg_ok "Updated Prefect"

    msg_info "Starting Prefect"
    systemctl start prefect-server prefect-worker
    msg_ok "Started Prefect"
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
echo -e "${GATEWAY}${BGN}http://${IP}:4200${CL}"
echo -e "${INFO}${YW}Log in with the auth string (user:password) from PREFECT_SERVER_API_AUTH_STRING in /opt/prefect_data/.env${CL}"
