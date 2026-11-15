#!/usr/bin/env bash
_CS_DEFAULT_URL="https://raw.githubusercontent.com/community-scripts/DevScripts/main"
_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../core}/core/build.func"
source "$_cs_boot" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/build.func")
# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://github.com/HiEventsDev/hi.events

APP="Hi-Events"
var_tags="${var_tags:-events;ticketing}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-6144}"
var_disk="${var_disk:-8}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

export var_mail_from="${var_mail_from:-}"
export var_smtp_host="${var_smtp_host:-}"
export var_smtp_port="${var_smtp_port:-}"
export var_smtp_user="${var_smtp_user:-}"
export var_smtp_pass="${var_smtp_pass:-}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/hi-events ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "hi-events" "HiEventsDev/hi.events"; then
    msg_info "Stopping Hi.Events"
    systemctl stop hi-events-frontend hi-events-queue hi-events-scheduler
    msg_ok "Stopped Hi.Events"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "hi-events" "HiEventsDev/hi.events" "tarball"

    msg_info "Building Hi.Events"
    rm -rf /opt/hi-events/backend/storage
    ln -s /opt/hi-events_data/storage /opt/hi-events/backend/storage
    ln -sf /opt/hi-events_data/.env /opt/hi-events/backend/.env
    cd /opt/hi-events/backend
    $STD composer install --no-dev --no-interaction --prefer-dist --optimize-autoloader
    $STD php artisan migrate --force
    $STD php artisan optimize:clear
    $STD php artisan storage:link
    chown -R www-data:www-data /opt/hi-events/backend /opt/hi-events_data/storage
    cd /opt/hi-events/frontend
    $STD yarn install --frozen-lockfile --network-timeout 600000
    $STD yarn build
    $STD yarn cache clean
    msg_ok "Built Hi.Events"

    msg_info "Starting Hi.Events"
    systemctl restart php8.4-fpm
    systemctl start hi-events-frontend hi-events-queue hi-events-scheduler
    msg_ok "Started Hi.Events"
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
echo -e "${GATEWAY}${BGN}https://${IP}/auth/register${CL}"
