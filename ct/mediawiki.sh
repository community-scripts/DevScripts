#!/usr/bin/env bash
_CS_DEFAULT_URL="https://raw.githubusercontent.com/community-scripts/DevScripts/main"
_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../core}/core/build.func"
source "$_cs_boot" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/build.func")
# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://www.mediawiki.org/

APP="MediaWiki"
var_tags="${var_tags:-wiki;documentation}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-6}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"
var_testurl="${var_testurl:-https://github.com/community-scripts/DevScripts/issues/2613}"

export var_admin_user="${var_admin_user:-}"
export var_admin_pass="${var_admin_pass:-}"
export var_wiki_name="${var_wiki_name:-}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -f /opt/mediawiki_data/LocalSettings.php ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  CURRENT=$(grep -oP "define\( 'MW_VERSION', '\K[0-9.]+" /opt/mediawiki/includes/Defines.php)
  if check_for_gh_tag "mediawiki" "wikimedia/mediawiki" "${CURRENT%.*}."; then
    msg_info "Stopping MediaWiki"
    systemctl stop nginx php8.3-fpm
    msg_ok "Stopped MediaWiki"

    CLEAN_INSTALL=1 CLEAN_INSTALL_KEEP="extensions skins" fetch_and_deploy_from_url "https://releases.wikimedia.org/mediawiki/${CURRENT%.*}/mediawiki-${CHECK_UPDATE_RELEASE}.tar.gz" "/opt/mediawiki"

    msg_info "Updating MediaWiki to ${CHECK_UPDATE_RELEASE}"
    rm -rf /opt/mediawiki/images
    ln -s /opt/mediawiki_data/images /opt/mediawiki/images
    ln -s /opt/mediawiki_data/LocalSettings.php /opt/mediawiki/LocalSettings.php
    cd /opt/mediawiki
    $STD php maintenance/run.php update --quick
    echo "$CHECK_UPDATE_RELEASE" >~/.mediawiki
    msg_ok "Updated MediaWiki to ${CHECK_UPDATE_RELEASE}"

    msg_info "Starting MediaWiki"
    systemctl start php8.3-fpm nginx
    msg_ok "Started MediaWiki"
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
echo -e "${INFO}${YW}Admin login: /opt/mediawiki_data/.env (inside the container)${CL}"
