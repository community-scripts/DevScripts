#!/usr/bin/env bash
_CS_DEFAULT_URL="https://raw.githubusercontent.com/community-scripts/DevScripts/main"
_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../core}/core/build.func"
source "$_cs_boot" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/build.func")
# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://github.com/mautic/mautic

APP="Mautic"
var_tags="${var_tags:-marketing;newsletter}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-5}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

export var_admin_user="${var_admin_user:-}"
export var_admin_email="${var_admin_email:-}"
export var_admin_pass="${var_admin_pass:-}"
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

  if [[ ! -f /opt/mautic/config/local.php ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "mautic" "mautic/mautic"; then
    msg_info "Stopping Mautic"
    systemctl stop cron nginx php8.4-fpm
    msg_ok "Stopped Mautic"

    fetch_and_deploy_gh_release "mautic" "mautic/mautic" "prebuild" "latest" "/opt/mautic" "*[0-9].zip"

    msg_info "Updating Mautic"
    cd /opt/mautic
    jq -r '.[]' deleted_files.txt | xargs -d '\n' rm -rf --
    rm -rf deleted_files.txt var/cache/prod
    chown -R www-data:www-data /opt/mautic
    $STD runuser -u www-data -- php bin/console mautic:update:apply --finish --no-interaction
    $STD runuser -u www-data -- php bin/console cache:clear
    msg_ok "Updated Mautic"

    msg_info "Starting Mautic"
    systemctl start php8.4-fpm nginx cron
    msg_ok "Started Mautic"
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
echo -e "${INFO}${YW}Admin credentials: /opt/mautic_data/.env (inside the container)${CL}"
