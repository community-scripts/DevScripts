#!/usr/bin/env bash
_CS_DEFAULT_URL="https://raw.githubusercontent.com/community-scripts/DevScripts/main"
_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../core}/core/build.func"
source "$_cs_boot" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/build.func")
# Copyright (c) 2021-2026 community-scripts ORG
# Author: untect (untect)
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://github.com/madeofpendletonwool/PinePods

APP="PinePods"
var_tags="${var_tags:-podcast;media}"
var_cpu="${var_cpu:-4}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-10}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
#var_arm64="${var_arm64:-no}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/pinepods ]]; then
    msg_error "No PinePods Installation Found!"
    exit
  fi

  if check_for_gh_release "pinepods" "madeofpendletonwool/PinePods"; then
    msg_info "Stopping PinePods"
    systemctl stop pinepods
    msg_ok "Stopped PinePods"

    RUST_PROFILE="minimal" setup_rust
    CLEAN_INSTALL=1 CLEAN_INSTALL_KEEP="downloads backups local-media" fetch_and_deploy_gh_release "pinepods" "madeofpendletonwool/PinePods" "tarball"
    PYTHON_VERSION=$(sed -n 's/^FROM python:\([0-9.]*\)-.*/\1/p' /opt/pinepods/dockerfile)
    TRUNK_VERSION=$(sed -n 's#.*trunk/releases/download/\(v[0-9.]*\)/.*#\1#p' /opt/pinepods/dockerfile)
    if [[ -z "$PYTHON_VERSION" || -z "$TRUNK_VERSION" ]]; then
      msg_error "Could not read the Python or trunk version from the PinePods dockerfile"
      exit 1
    fi
    setup_uv
    fetch_and_deploy_gh_release "trunk" "trunk-rs/trunk" "prebuild" "$TRUNK_VERSION" "/usr/local/bin" "trunk-$(arch_resolve "x86_64" "aarch64")-unknown-linux-gnu.tar.gz"

    msg_info "Rebuilding PinePods"
    $STD rustup target add wasm32-unknown-unknown
    cd /opt/pinepods/web || msg_error "Directory /opt/pinepods/web not found" && exit 1
    RUSTFLAGS="--cfg=web_sys_unstable_apis --cfg getrandom_backend=\"wasm_js\"" $STD trunk build --features server_build --release
    rm -rf /var/www/html
    cp -r /opt/pinepods/web/dist /var/www/html
    cp -r /opt/pinepods/web/src/translations /var/www/html/static/translations
    cd /opt/pinepods/rust-api || msg_error "Directory /opt/pinepods/rust-api not found" && exit 1
    $STD cargo build --release
    cp /opt/pinepods/rust-api/target/release/pinepods-api /usr/local/bin/pinepods-api
    rm -rf /opt/pinepods/web/target /opt/pinepods/web/dist /opt/pinepods/rust-api/target
    cp ~/.pinepods /pinepods/current_version
    msg_ok "Rebuilt PinePods"

    msg_info "Updating Python Runtime"
    $STD uv venv --python "$PYTHON_VERSION" /opt/pinepods/.venv
    $STD uv pip install --python /opt/pinepods/.venv/bin/python -r /opt/pinepods/requirements.txt
    msg_ok "Updated Python Runtime"

    msg_info "Starting PinePods"
    systemctl start pinepods
    msg_ok "Started PinePods"
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
echo -e "${GATEWAY}${BGN}http://${IP}:8040${CL}"
