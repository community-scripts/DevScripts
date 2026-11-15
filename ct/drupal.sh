#!/usr/bin/env bash
_CS_DEFAULT_URL="https://raw.githubusercontent.com/community-scripts/DevScripts/main"
_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../core}/core/build.func"
source "$_cs_boot" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/build.func")
# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://www.drupal.org/

APP="Drupal"
var_tags="${var_tags:-cms;website}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

export var_admin_user="${var_admin_user:-}"
export var_admin_pass="${var_admin_pass:-}"
export var_admin_email="${var_admin_email:-}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -f /opt/drupal/web/sites/default/settings.php ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  setup_composer
  cd /opt/drupal
  msg_info "Checking for update: Drupal"
  LATEST=$(composer show drupal/core --latest --minor-only --format=json | jq -r '.latest')
  if [[ "$LATEST" == "$(cat ~/.drupal)" ]]; then
    msg_ok "No update available: Drupal (${LATEST})"
    exit
  fi
  msg_ok "Update available: Drupal $(cat ~/.drupal) → ${LATEST}"

  msg_info "Stopping Drupal"
  systemctl stop nginx php8.4-fpm
  msg_ok "Stopped Drupal"

  msg_info "Updating Drupal"
  $STD composer update "drupal/core-*" --with-all-dependencies --no-interaction
  $STD vendor/bin/drush updatedb -y
  $STD vendor/bin/drush cache:rebuild
  chown -R www-data:www-data web/sites/default/files
  jq -r '.packages[] | select(.name == "drupal/core") | .version' composer.lock >~/.drupal
  msg_ok "Updated Drupal to $(cat ~/.drupal)"

  msg_info "Starting Drupal"
  systemctl start php8.4-fpm nginx
  msg_ok "Started Drupal"
  msg_ok "Updated successfully!"
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW}Access it using the following URL:${CL}"
echo -e "${GATEWAY}${BGN}http://${IP}${CL}"
echo -e "${INFO}${YW}Admin login: /opt/drupal_data/.env (inside the container)${CL}"
