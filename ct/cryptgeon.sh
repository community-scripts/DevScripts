#!/usr/bin/env bash
_CS_DEFAULT_URL="https://raw.githubusercontent.com/community-scripts/DevScripts/main"
_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../core}/core/build.func"
source "$_cs_boot" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/build.func")
# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://github.com/cupcakearmy/cryptgeon

APP="Cryptgeon"
var_tags="${var_tags:-privacy;sharing;encryption}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
#var_arm64="${var_arm64:-no}" # unset = ask the user; set yes/no only when verified
var_unprivileged="${var_unprivileged:-1}"
var_testurl="${var_testurl:-https://github.com/community-scripts/DevScripts/issues/2615}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/cryptgeon ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "cryptgeon" "cupcakearmy/cryptgeon"; then
    msg_info "Stopping Cryptgeon"
    systemctl stop cryptgeon
    msg_ok "Stopped Cryptgeon"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "cryptgeon" "cupcakearmy/cryptgeon" "tarball"
    RUST_PROFILE="minimal" setup_rust
    NODE_VERSION="24" NODE_MODULE="pnpm@$(jq -r '.packageManager | split("@")[1]' /opt/cryptgeon/package.json)" setup_nodejs

    msg_info "Building Cryptgeon"
    cd /opt/cryptgeon
    $STD pnpm install --frozen-lockfile
    $STD pnpm run build
    cd /opt/cryptgeon/packages/backend
    $STD cargo build --release --locked
    cp target/release/cryptgeon /opt/cryptgeon/cryptgeon
    rm -rf /opt/cryptgeon/packages/backend/target /opt/cryptgeon/node_modules /opt/cryptgeon/packages/*/node_modules
    msg_ok "Built Cryptgeon"

    msg_info "Starting Cryptgeon"
    systemctl start cryptgeon
    msg_ok "Started Cryptgeon"
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
echo -e "${GATEWAY}${BGN}https://${IP}${CL}"
