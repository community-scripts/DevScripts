#!/usr/bin/env bash
_CS_DEFAULT_URL="https://raw.githubusercontent.com/community-scripts/DevScripts/main"
_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../core}/core/build.func"
source "$_cs_boot" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/build.func")
# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://github.com/argilla-io/argilla

APP="Argilla"
var_tags="${var_tags:-ai;annotation;datasets}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-3072}"
var_disk="${var_disk:-8}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"
var_testurl="${var_testurl:-https://github.com/community-scripts/DevScripts/issues/2638}"

export var_argilla_password="${var_argilla_password:-}"
export var_argilla_api_key="${var_argilla_api_key:-}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/argilla ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "argilla" "argilla-io/argilla"; then
    msg_info "Stopping Argilla"
    systemctl stop argilla-worker argilla
    msg_ok "Stopped Argilla"

    PYTHON_VERSION="3.13" setup_uv

    msg_info "Updating Argilla"
    $STD uv pip install --upgrade --python /opt/argilla/.venv/bin/python "argilla-server==${CHECK_UPDATE_RELEASE#v}" "click<8.2"
    cd /opt/argilla_data
    set -a && source /opt/argilla_data/.env && set +a
    $STD /opt/argilla/.venv/bin/python -m argilla_server database migrate
    cat <<EOF >~/.argilla
${CHECK_UPDATE_RELEASE#v}
EOF
    msg_ok "Updated Argilla"

    msg_info "Starting Argilla"
    systemctl start argilla argilla-worker
    msg_ok "Started Argilla"
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
echo -e "${GATEWAY}${BGN}http://${IP}:6900${CL}"
echo -e "${INFO}${YW}Credentials and API key: /opt/argilla_data/.env${CL}"
