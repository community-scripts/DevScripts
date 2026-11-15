#!/usr/bin/env bash
_CS_DEFAULT_URL="https://raw.githubusercontent.com/community-scripts/DevScripts/main"
_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../core}/core/build.func"
source "$_cs_boot" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/build.func")
# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://github.com/hoppscotch/hoppscotch

APP="Hoppscotch"
var_tags="${var_tags:-api;development;testing}"
var_cpu="${var_cpu:-4}"
var_ram="${var_ram:-6144}"
var_disk="${var_disk:-8}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
#var_arm64="${var_arm64:-no}" # unset = ask the user; set yes/no only when verified
var_unprivileged="${var_unprivileged:-1}"
var_testurl="${var_testurl:-https://github.com/community-scripts/DevScripts/issues/2596}"

export var_smtp_url="${var_smtp_url:-}"
export var_mail_from="${var_mail_from:-}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/hoppscotch ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "hoppscotch" "hoppscotch/hoppscotch"; then
    msg_info "Stopping Hoppscotch"
    systemctl stop hoppscotch-backend hoppscotch-webapp
    msg_ok "Stopped Hoppscotch"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "hoppscotch" "hoppscotch/hoppscotch" "tarball"
    NODE_VERSION="24" NODE_MODULE="$(jq -r '.packageManager' /opt/hoppscotch/package.json)" setup_nodejs

    msg_info "Building Hoppscotch"
    ln -sf /opt/hoppscotch_data/frontend.env /opt/hoppscotch/.env
    ln -sf /opt/hoppscotch_data/.env /opt/hoppscotch/packages/hoppscotch-backend/.env
    cd /opt/hoppscotch
    $STD pnpm install --frozen-lockfile
    cd /opt/hoppscotch/packages/hoppscotch-backend
    $STD pnpm exec prisma generate
    $STD pnpm run build
    $STD pnpm exec prisma migrate deploy
    cd /opt/hoppscotch/packages/hoppscotch-selfhost-web
    HOPP_ALLOW_RUNTIME_ENV=true $STD pnpm run build --sourcemap false
    cd /opt/hoppscotch/packages/hoppscotch-selfhost-web/webapp-server
    CGO_ENABLED=0 $STD go build -o webapp-server .
    $STD go clean -cache -modcache
    cd /opt/hoppscotch/packages/hoppscotch-sh-admin
    HOPP_ALLOW_RUNTIME_ENV=true $STD pnpm run build --outDir dist-subpath-access --base /admin/
    msg_ok "Built Hoppscotch"

    msg_info "Starting Hoppscotch"
    systemctl start hoppscotch-backend hoppscotch-webapp
    msg_ok "Started Hoppscotch"
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
echo -e "${GATEWAY}${BGN}http://${IP}/admin${CL}"
