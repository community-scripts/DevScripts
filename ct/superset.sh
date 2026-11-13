#!/usr/bin/env bash
_CS_DEFAULT_URL="https://raw.githubusercontent.com/community-scripts/DevScripts/main"
_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../core}/core/build.func"
source "$_cs_boot" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/build.func")
# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://github.com/apache/superset

APP="Superset"
var_tags="${var_tags:-analytics;bi;dashboard}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-5}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"
var_testurl="${var_testurl:-https://github.com/community-scripts/DevScripts/issues/2618}"

export var_admin_pass="${var_admin_pass:-}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/superset ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "superset" "apache/superset"; then
    curl_with_retry "https://raw.githubusercontent.com/apache/superset/${CHECK_UPDATE_RELEASE}/requirements/base.txt" /opt/superset/requirements.txt
    sed -i '/^-e /d' /opt/superset/requirements.txt

    msg_info "Stopping Apache Superset"
    systemctl stop superset
    msg_ok "Stopped Apache Superset"

    PYTHON_VERSION="3.11" setup_uv

    msg_info "Updating Apache Superset"
    $STD uv pip install --python /opt/superset/.venv/bin/python -r /opt/superset/requirements.txt "apache-superset[postgres]==${CHECK_UPDATE_RELEASE}"
    set -a && source /opt/superset_data/.env && set +a
    $STD /opt/superset/.venv/bin/superset db upgrade
    $STD /opt/superset/.venv/bin/superset init
    cat <<EOF >~/.superset
${CHECK_UPDATE_RELEASE}
EOF
    msg_ok "Updated Apache Superset"

    msg_info "Starting Apache Superset"
    systemctl start superset
    msg_ok "Started Apache Superset"
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
echo -e "${GATEWAY}${BGN}http://${IP}:8088${CL}"
echo -e "${INFO}${YW}Login: admin / SUPERSET_ADMIN_PASSWORD in /opt/superset_data/.env (inside the container)${CL}"
