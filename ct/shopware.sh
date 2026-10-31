#!/usr/bin/env bash
_CS_DEFAULT_URL="https://raw.githubusercontent.com/community-scripts/DevScripts/main"
_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../core}/core/build.func"
source "$_cs_boot" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/build.func")

# Copyright (c) 2021-2026 community-scripts ORG
# Author: TaiKamilla
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://www.shopware.com/ | Github: https://github.com/shopware/shopware

APP="Shopware"
var_tags="${var_tags:-ecommerce;shop}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-6144}"
var_disk="${var_disk:-20}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

export var_admin_user="${var_admin_user:-}"
export var_admin_pass="${var_admin_pass:-}"
export var_admin_email="${var_admin_email:-}"
export var_opensearch="${var_opensearch:-}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/shopware ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "valkey" "valkey-io/valkey"; then
    systemctl stop valkey@cache valkey@persistent
    CLEAN_INSTALL=1 fetch_and_deploy_from_url "https://download.valkey.io/releases/valkey-${CHECK_UPDATE_RELEASE}-noble-$(arch_resolve "x86_64" "arm64").tar.gz" "/opt/valkey"
    cat <<EOF >~/.valkey
${CHECK_UPDATE_RELEASE}
EOF
    systemctl start valkey@cache valkey@persistent
    msg_ok "Updated Valkey"
  fi

  if check_for_gh_release "shopware" "shopware/shopware"; then
    msg_info "Stopping Services"
    systemctl stop shopware-worker shopware-scheduler
    msg_ok "Stopped Services"

    msg_info "Updating Shopware"
    cd /opt/shopware
    export COMPOSER_ALLOW_SUPERUSER=1
    $STD php bin/console sales-channel:maintenance:enable --all
    create_backup /opt/shopware/.env.local /opt/shopware/config/packages/prod
    $STD php bin/console system:update:prepare
    if ! $STD composer update --no-interaction --no-dev --prefer-dist --with-all-dependencies; then
      restore_backup
      $STD php bin/console sales-channel:maintenance:disable --all
      chown -R www-data:www-data /opt/shopware
      systemctl start shopware-worker shopware-scheduler
      msg_error "Composer update failed. The shop is unchanged, check the output above."
      exit 1
    fi
    restore_backup
    $STD php bin/console system:update:finish
    $STD php bin/console sales-channel:maintenance:disable --all
    $STD php bin/console cache:clear
    jq -r '.packages[] | select(.name == "shopware/core") | .version' /opt/shopware/composer.lock | sed 's/^v//' >~/.shopware
    chown -R www-data:www-data /opt/shopware
    msg_ok "Updated Shopware"

    msg_info "Starting Services"
    systemctl start shopware-worker shopware-scheduler
    msg_ok "Started Services"
    msg_ok "Updated successfully!"
  fi
  exit
}

start
build_container
description

msg_ok "Completed successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW}Access it using the following URL:${CL}"
echo -e "${GATEWAY}${BGN}http://${IP}/admin${CL}"
