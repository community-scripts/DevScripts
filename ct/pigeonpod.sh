#!/usr/bin/env bash
_CS_DEFAULT_URL="https://raw.githubusercontent.com/community-scripts/DevScripts/main"
_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../core}/core/build.func"
source "$_cs_boot" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/build.func")
# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://github.com/aizhimou/pigeon-pod

APP="PigeonPod"
var_tags="${var_tags:-media;podcast;youtube}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-20}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"
var_testurl="${var_testurl:-https://github.com/community-scripts/DevScripts/issues/2334}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/pigeonpod ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  msg_info "Updating yt-dlp"
  $STD yt-dlp -U
  msg_ok "Updated yt-dlp"

  if check_for_gh_release "pigeonpod" "aizhimou/pigeon-pod"; then
    msg_info "Stopping PigeonPod"
    systemctl stop pigeonpod
    msg_ok "Stopped PigeonPod"

    NODE_VERSION="22" setup_nodejs
    JAVA_VERSION="17" setup_java
    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "pigeonpod" "aizhimou/pigeon-pod" "tarball"

    msg_info "Building PigeonPod"
    cd /opt/pigeonpod/frontend
    $STD npm ci
    $STD npm run build
    mv /opt/pigeonpod/frontend/dist /opt/pigeonpod/backend/src/main/resources/static
    cd /opt/pigeonpod/backend
    $STD mvn -B clean package -DskipTests
    mv /opt/pigeonpod/backend/target/pigeon-pod-*.jar /opt/pigeonpod/pigeon-pod.jar
    rm -rf /opt/pigeonpod/frontend/node_modules /opt/pigeonpod/backend/target
    msg_ok "Built PigeonPod"

    msg_info "Starting PigeonPod"
    systemctl start pigeonpod
    msg_ok "Started PigeonPod"
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
echo -e "${GATEWAY}${BGN}http://${IP}:8080${CL}"
