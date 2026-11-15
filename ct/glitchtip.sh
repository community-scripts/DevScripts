#!/usr/bin/env bash
_CS_DEFAULT_URL="https://raw.githubusercontent.com/community-scripts/DevScripts/main"
_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../core}/core/build.func"
source "$_cs_boot" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/build.func")
# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://gitlab.com/glitchtip/glitchtip-backend

APP="GlitchTip"
var_tags="${var_tags:-monitoring;error-tracking;sentry}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-8}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"
var_testurl="${var_testurl:-https://github.com/community-scripts/DevScripts/issues/2608}"

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

  if [[ ! -d /opt/glitchtip ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gl_release "glitchtip" "glitchtip/glitchtip-backend"; then
    msg_info "Stopping GlitchTip"
    systemctl stop glitchtip
    msg_ok "Stopped GlitchTip"

    CLEAN_INSTALL=1 CLEAN_INSTALL_KEEP=".venv" fetch_and_deploy_gl_release "glitchtip" "glitchtip/glitchtip-backend" "tarball"
    fetch_and_deploy_from_url "https://gitlab.com/api/v4/projects/15449363/jobs/artifacts/v$(cat ~/.glitchtip)/download?job=build-assets" "/opt/glitchtip/frontend"
    PYTHON_VERSION="3.14" setup_uv

    msg_info "Updating GlitchTip"
    mv /opt/glitchtip/frontend/glitchtip-frontend/browser /opt/glitchtip/dist
    rm -rf /opt/glitchtip/frontend
    cd /opt/glitchtip
    $STD uv sync --frozen --no-dev --no-install-project --python 3.14
    sed -i "s/^GLITCHTIP_VERSION=.*/GLITCHTIP_VERSION=$(cat ~/.glitchtip)/" /opt/glitchtip_data/.env
    set -a && source /opt/glitchtip_data/.env && set +a
    $STD .venv/bin/python manage.py collectstatic --noinput
    $STD .venv/bin/python manage.py init_database
    msg_ok "Updated GlitchTip"

    msg_info "Starting GlitchTip"
    systemctl start glitchtip
    msg_ok "Started GlitchTip"
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
echo -e "${GATEWAY}${BGN}http://${IP}:8000${CL}"
echo -e "${INFO}${YW}Login: DJANGO_SUPERUSER_EMAIL / DJANGO_SUPERUSER_PASSWORD in /opt/glitchtip_data/.env (inside the container)${CL}"
