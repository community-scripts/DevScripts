#!/usr/bin/env bash
_CS_DEFAULT_URL="https://raw.githubusercontent.com/community-scripts/DevScripts/main"
_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../core}/core/build.func"
source "$_cs_boot" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/build.func")
# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://github.com/inovector/mixpost

APP="Mixpost"
var_tags="${var_tags:-social-media;scheduler}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-6}"
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

  if [[ ! -d /opt/mixpost ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "mixpost" "inovector/mixpost"; then
    msg_info "Stopping Mixpost"
    systemctl stop mixpost-scheduler mixpost-horizon
    msg_ok "Stopped Mixpost"

    setup_composer

    msg_info "Updating Mixpost"
    cd /opt/mixpost
    $STD composer require "inovector/mixpost:${CHECK_UPDATE_RELEASE#v}" --update-no-dev --update-with-all-dependencies --no-interaction
    $STD php artisan migrate --force
    $STD php artisan optimize:clear
    $STD php artisan mixpost:clear-services-cache
    $STD php artisan mixpost:clear-settings-cache
    $STD php artisan optimize
    chown -R www-data:www-data /opt/mixpost /opt/mixpost_data
    cat <<EOF >~/.mixpost
${CHECK_UPDATE_RELEASE#v}
EOF
    msg_ok "Updated Mixpost"

    msg_info "Starting Mixpost"
    systemctl reload php8.4-fpm
    systemctl start mixpost-horizon mixpost-scheduler
    msg_ok "Started Mixpost"
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
echo -e "${INFO}${YW}Admin login: /opt/mixpost_data/.env (inside the container)${CL}"
