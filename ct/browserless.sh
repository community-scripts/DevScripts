#!/usr/bin/env bash
_CS_DEFAULT_URL="https://raw.githubusercontent.com/community-scripts/DevScripts/main"
_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../core}/core/build.func"
source "$_cs_boot" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/build.func")
# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://github.com/browserless/browserless

APP="Browserless"
var_tags="${var_tags:-automation;browser;headless}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-8}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
#var_arm64="${var_arm64:-no}" # unset = ask the user; set yes/no only when verified
var_unprivileged="${var_unprivileged:-1}"
var_testurl="${var_testurl:-https://github.com/community-scripts/DevScripts/issues/2622}"

export var_browserless_token="${var_browserless_token:-}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/browserless ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "browserless" "browserless/browserless"; then
    msg_info "Stopping Browserless"
    systemctl stop browserless
    msg_ok "Stopped Browserless"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "browserless" "browserless/browserless" "tarball"
    NODE_VERSION="$(grep -oP 'ARG NODE_VERSION=v\K[0-9]+' /opt/browserless/docker/base/Dockerfile)" setup_nodejs

    msg_info "Building Browserless"
    cd /opt/browserless
    cp fonts/*.ttf /usr/share/fonts/truetype/
    cp fonts/fonts.conf /etc/fonts/local.conf
    $STD fc-cache -f
    $STD npm ci
    rm -rf src/routes/{chrome,edge,firefox,webkit} # the routes upstream leaves out of its chromium image
    $STD npm run build
    $STD npm run build:function
    $STD npm run install:debugger
    $STD npm prune --omit=dev
    msg_ok "Built Browserless"

    msg_info "Updating Chromium"
    rm -rf /root/.cache/ms-playwright/.links # lets Playwright delete the browsers of the previous pin
    $STD ./node_modules/playwright-core/cli.js install --with-deps chromium
    $STD node scripts/install-playwright-ffmpeg.js
    msg_ok "Updated Chromium"

    msg_info "Starting Browserless"
    systemctl start browserless
    msg_ok "Started Browserless"
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
echo -e "${GATEWAY}${BGN}http://${IP}:3000/docs${CL}"
echo -e "${INFO}${YW}The API token is TOKEN in /opt/browserless_data/.env${CL}"
