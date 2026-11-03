#!/usr/bin/env bash
_CS_DEFAULT_URL="https://raw.githubusercontent.com/community-scripts/DevScripts/main"
_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../core}/core/build.func"
source "$_cs_boot" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/build.func")
# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://github.com/figranium/figranium

APP="Figranium"
var_tags="${var_tags:-automation;browser;scraping}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-3072}"
var_disk="${var_disk:-10}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"
var_testurl="${var_testurl:-https://github.com/community-scripts/DevScripts/issues/2363}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/figranium ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "figranium" "figranium/figranium"; then
    msg_info "Stopping Figranium"
    systemctl stop figranium
    msg_ok "Stopped Figranium"

    NODE_VERSION="24" setup_nodejs
    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "figranium" "figranium/figranium" "tarball"

    msg_info "Building Figranium"
    cd /opt/figranium
    export FIGRANIUM_SKIP_PLAYWRIGHT_INSTALL=1
    $STD npm ci --include=dev
    $STD npm run build
    $STD npm prune --omit=dev
    mkdir -p /opt/figranium/src/public
    ln -s /opt/figranium_data/data /opt/figranium/data
    ln -s /opt/figranium_data/captures /opt/figranium/public/captures
    ln -s /opt/figranium_data/captures /opt/figranium/src/public/captures
    msg_ok "Built Figranium"

    msg_info "Updating Chromium for Figranium"
    $STD npx playwright install --with-deps chromium
    msg_ok "Updated Chromium for Figranium"

    msg_info "Starting Figranium"
    systemctl start figranium
    msg_ok "Started Figranium"
    msg_ok "Updated Figranium successfully!"
  fi

  if check_for_gh_release "novnc" "novnc/noVNC"; then
    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "novnc" "novnc/noVNC" "tarball" "latest" "/opt/novnc"
    msg_ok "Updated noVNC successfully!"
  fi
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW}Access it using the following URL:${CL}"
echo -e "${GATEWAY}${BGN}http://${IP}:11345${CL}"
