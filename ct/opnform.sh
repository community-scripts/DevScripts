#!/usr/bin/env bash
_CS_DEFAULT_URL="https://raw.githubusercontent.com/community-scripts/DevScripts/main"
_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../core}/core/build.func"
source "$_cs_boot" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/build.func")
# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://github.com/OpnForm/OpnForm

APP="OpnForm"
var_tags="${var_tags:-forms;survey}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-6144}"
var_disk="${var_disk:-8}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/opnform ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "opnform" "OpnForm/OpnForm"; then
    msg_info "Stopping OpnForm"
    systemctl stop opnform-client opnform-worker opnform-scheduler
    msg_ok "Stopped OpnForm"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "opnform" "OpnForm/OpnForm" "tarball"

    msg_info "Building OpnForm API"
    rm -rf /opt/opnform/api/storage
    ln -s /opt/opnform_data/storage /opt/opnform/api/storage
    ln -sf /opt/opnform_data/api.env /opt/opnform/api/.env
    cd /opt/opnform/api
    $STD composer install --no-dev --no-interaction --prefer-dist --optimize-autoloader
    $STD php artisan storage:link
    $STD php artisan migrate --force
    $STD php artisan optimize:clear
    $STD php artisan optimize
    chown -R www-data:www-data /opt/opnform/api /opt/opnform_data/storage
    msg_ok "Built OpnForm API"

    msg_info "Building OpnForm Client"
    cd /opt/opnform/client
    export NODE_OPTIONS="--max-old-space-size=4096" NUXT_TELEMETRY_DISABLED=1
    $STD npm ci
    $STD npm run build
    rm -rf /opt/opnform/client/node_modules
    msg_ok "Built OpnForm Client"

    msg_info "Starting OpnForm"
    systemctl restart php8.3-fpm
    systemctl start opnform-client opnform-worker opnform-scheduler
    msg_ok "Started OpnForm"
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
echo -e "${GATEWAY}${BGN}http://${IP}${CL}"
