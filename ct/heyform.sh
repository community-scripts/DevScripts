#!/usr/bin/env bash
_CS_DEFAULT_URL="https://raw.githubusercontent.com/community-scripts/DevScripts/main"
_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../core}/core/build.func"
source "$_cs_boot" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/build.func")
# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://github.com/heyform/heyform

APP="HeyForm"
var_tags="${var_tags:-forms;survey}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-3072}"
var_disk="${var_disk:-10}"
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

  if [[ ! -d /opt/heyform ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "heyform" "heyform/heyform"; then
    msg_info "Stopping HeyForm"
    systemctl stop heyform
    msg_ok "Stopped HeyForm"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "heyform" "heyform/heyform" "tarball"
    NODE_VERSION="22" NODE_MODULE="pnpm@$(grep -oP 'pnpm@\K[0-9.]+' /opt/heyform/Dockerfile)" setup_nodejs

    msg_info "Building HeyForm"
    cd /opt/heyform
    HEYFORM_SKIP_SHARED_BUILD=1 $STD pnpm install --frozen-lockfile
    cp packages/server/view/index.html packages/webapp/index.html
    $STD pnpm build:shared
    $STD pnpm --filter ./packages/server build
    $STD pnpm --filter ./packages/webapp build
    mkdir -p packages/server/static
    cp -R packages/webapp/dist/static/. packages/server/static/
    cp packages/webapp/dist/index.html packages/server/view/index.html
    rm -rf ~/.cache/pnpm ~/.local/share/pnpm/store
    ln -sfn /opt/heyform_data/uploads /opt/heyform/packages/server/static/upload
    msg_ok "Built HeyForm"

    msg_info "Starting HeyForm"
    systemctl start heyform
    msg_ok "Started HeyForm"
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
