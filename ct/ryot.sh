#!/usr/bin/env bash
_CS_DEFAULT_URL="https://raw.githubusercontent.com/community-scripts/DevScripts/main"
_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../core}/core/build.func"
source "$_cs_boot" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/build.func")
# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://github.com/IgnisDa/ryot

APP="Ryot"
var_tags="${var_tags:-media;tracker;fitness}"
var_cpu="${var_cpu:-4}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-10}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
#var_arm64="${var_arm64:-yes}" # built from source, upstream ships arm64 images of the same build, but not yet run on arm64
var_unprivileged="${var_unprivileged:-1}"
var_testurl="${var_testurl:-https://github.com/community-scripts/DevScripts/issues/2406}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/ryot ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "ryot" "IgnisDa/ryot"; then
    msg_info "Stopping Ryot"
    systemctl stop ryot-frontend ryot-backend
    msg_ok "Stopped Ryot"

    NODE_VERSION="24" NODE_MODULE="yarn" setup_nodejs
    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "ryot" "IgnisDa/ryot" "tarball"
    RUST_TOOLCHAIN="$(sed -n 's/^channel = "\(.*\)"/\1/p' /opt/ryot/rust-toolchain.toml)" RUST_PROFILE="minimal" setup_rust

    msg_info "Building Ryot (Patience)"
    cd /opt/ryot
    $STD yarn workspaces focus @ryot/root @ryot/frontend @ryot/transactional
    $STD yarn workspace @ryot/transactional build
    $STD yarn workspace @ryot/transactional copy-templates
    APP_VERSION="v$(cat ~/.ryot)" UNKEY_ROOT_KEY="" CARGO_PROFILE_RELEASE_LTO=false CARGO_PROFILE_RELEASE_CODEGEN_UNITS=16 \
      $STD cargo build --locked --release --bin backend
    mv /opt/ryot/target/release/backend /opt/ryot/backend
    $STD yarn workspace @ryot/frontend build
    $STD yarn workspaces focus @ryot/frontend --production
    rm -rf /opt/ryot/target ~/.cargo/registry ~/.cargo/git ~/.yarn/berry
    msg_ok "Built Ryot"

    msg_info "Starting Ryot"
    systemctl start ryot-backend ryot-frontend
    msg_ok "Started Ryot"
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
echo -e "${GATEWAY}${BGN}http://${IP}:8000${CL}"
