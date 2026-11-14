#!/usr/bin/env bash
_CS_DEFAULT_URL="https://raw.githubusercontent.com/community-scripts/DevScripts/main"
_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../core}/core/build.func"
source "$_cs_boot" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/build.func")
# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://github.com/Smaug6739/Alexandrie

APP="Alexandrie"
var_tags="${var_tags:-notes;markdown;knowledge-base}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-6}"
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

  if [[ ! -d /opt/alexandrie ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "rustfs" "rustfs/rustfs"; then
    msg_info "Stopping RustFS"
    systemctl stop alexandrie-backend rustfs
    msg_ok "Stopped RustFS"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "rustfs" "rustfs/rustfs" "prebuild" "latest" "/opt/rustfs" "rustfs-linux-$(arch_resolve x86_64 aarch64)-gnu-*.zip"
    chmod +x /opt/rustfs/rustfs

    msg_info "Starting RustFS"
    systemctl start rustfs alexandrie-backend
    msg_ok "Started RustFS"
  fi

  if check_for_gh_release "alexandrie" "Smaug6739/Alexandrie"; then
    msg_info "Stopping Alexandrie"
    systemctl stop alexandrie-frontend alexandrie-backend
    msg_ok "Stopped Alexandrie"

    setup_go
    NODE_VERSION="24" NODE_MODULE="bun" setup_nodejs
    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "alexandrie" "Smaug6739/Alexandrie" "tarball"

    msg_info "Building Alexandrie"
    cd /opt/alexandrie/backend
    CGO_ENABLED=0 $STD go build -o alexandrie .
    $STD go clean -cache -modcache
    cd /opt/alexandrie/frontend
    $STD bun install --frozen-lockfile
    NODE_ENV=production $STD bun run build
    rm -rf node_modules .nuxt ~/.bun/install/cache
    msg_ok "Built Alexandrie"

    msg_info "Starting Alexandrie"
    systemctl start alexandrie-backend alexandrie-frontend
    msg_ok "Started Alexandrie"
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
