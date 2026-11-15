#!/usr/bin/env bash
_CS_DEFAULT_URL="https://raw.githubusercontent.com/community-scripts/DevScripts/main"
_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../core}/core/build.func"
source "$_cs_boot" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/build.func")
# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://github.com/rybbit-io/rybbit

APP="Rybbit"
var_tags="${var_tags:-analytics;tracking}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-8}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
#var_arm64="${var_arm64:-no}" # unset = ask the user; set yes/no only when verified
var_unprivileged="${var_unprivileged:-1}"

export var_base_url="${var_base_url:-}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/rybbit ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "rybbit" "rybbit-io/rybbit"; then
    msg_info "Stopping Rybbit"
    systemctl stop rybbit-client rybbit-server
    msg_ok "Stopped Rybbit"

    NODE_VERSION="24" setup_nodejs
    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "rybbit" "rybbit-io/rybbit" "tarball"

    msg_info "Building Rybbit"
    cd /opt/rybbit/shared
    $STD npm install
    $STD npm run build
    cd /opt/rybbit/server
    PUPPETEER_SKIP_DOWNLOAD=true $STD npm ci --legacy-peer-deps
    rm -rf node_modules/@rybbit/shared
    mkdir -p node_modules/@rybbit/shared
    cp -r /opt/rybbit/shared/package.json /opt/rybbit/shared/dist node_modules/@rybbit/shared/
    $STD npm run build
    cd /opt/rybbit/client
    $STD npm ci --legacy-peer-deps
    rm -rf node_modules/@rybbit/shared
    mkdir -p node_modules/@rybbit/shared
    cp -r /opt/rybbit/shared/package.json /opt/rybbit/shared/dist node_modules/@rybbit/shared/
    NEXT_TELEMETRY_DISABLED=1 NEXT_PUBLIC_BACKEND_URL="$(sed -n 's/^BASE_URL=//p' /opt/rybbit_data/.env)" NEXT_PUBLIC_DISABLE_SIGNUP="$(sed -n 's/^DISABLE_SIGNUP=//p' /opt/rybbit_data/.env)" $STD npm run build
    cp -r public .next/standalone/
    cp -r .next/static .next/standalone/.next/
    rm -rf node_modules .next/cache ~/.npm
    msg_ok "Built Rybbit"

    msg_info "Starting Rybbit"
    systemctl start rybbit-server rybbit-client
    msg_ok "Started Rybbit"
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
echo -e "${GATEWAY}${BGN}https://${IP}/signup${CL}"
