#!/usr/bin/env bash
_CS_DEFAULT_URL="https://raw.githubusercontent.com/community-scripts/DevScripts/main"
_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../core}/core/build.func"
source "$_cs_boot" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/build.func")
# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://github.com/redis/RedisInsight

APP="Redis Insight"
var_tags="${var_tags:-database;redis;valkey}"
var_cpu="${var_cpu:-4}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-12}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
#var_arm64="${var_arm64:-no}" # unset = ask the user; set yes/no only when verified
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/redisinsight ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "redisinsight" "redis/RedisInsight"; then
    msg_info "Stopping Redis Insight"
    systemctl stop redisinsight
    msg_ok "Stopped Redis Insight"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "redisinsight" "redis/RedisInsight" "tarball"
    NODE_VERSION="$(cut -d. -f1 /opt/redisinsight/.nvmrc)" NODE_MODULE="yarn" setup_nodejs

    msg_info "Building Redis Insight"
    cd /opt/redisinsight
    SKIP_POSTINSTALL=1 ELECTRON_SKIP_BINARY_DOWNLOAD=1 $STD yarn install
    $STD yarn --cwd redisinsight/api install
    $STD yarn build:ui
    $STD yarn build:statics
    $STD yarn build:api
    SKIP_API_CLIENT_GEN=1 $STD yarn --cwd redisinsight/api install --production
    cp redisinsight/api/.yarnclean.prod redisinsight/api/.yarnclean
    $STD yarn --cwd redisinsight/api autoclean --force
    rm -rf node_modules redisinsight/ui/src/packages/*/node_modules
    $STD yarn cache clean
    msg_ok "Built Redis Insight"

    msg_info "Starting Redis Insight"
    systemctl start redisinsight
    msg_ok "Started Redis Insight"
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
echo -e "${GATEWAY}${BGN}http://${IP}:5540${CL}"
