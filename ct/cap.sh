#!/usr/bin/env bash
_CS_DEFAULT_URL="https://raw.githubusercontent.com/community-scripts/DevScripts/main"
_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../core}/core/build.func"
source "$_cs_boot" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/build.func")
# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://github.com/CapSoftware/Cap

APP="Cap"
var_tags="${var_tags:-screen-recording;video;sharing}"
var_cpu="${var_cpu:-4}"
var_ram="${var_ram:-8192}"
var_disk="${var_disk:-20}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-no}" # MySQL 8 comes from Oracle's APT repo, which has no arm64 builds for Debian
var_unprivileged="${var_unprivileged:-1}"
var_testurl="${var_testurl:-https://github.com/community-scripts/DevScripts/issues/2672}"

export var_cap_url="${var_cap_url:-}"
export var_resend_api_key="${var_resend_api_key:-}"
export var_resend_from_domain="${var_resend_from_domain:-}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/cap ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "cap" "CapSoftware/Cap" "" "" "cap-v"; then
    msg_info "Stopping Cap"
    systemctl stop cap-web cap-media-server cap-rustfs
    msg_ok "Stopped Cap"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "rustfs" "rustfs/rustfs" "prebuild" "latest" "/opt/rustfs" "rustfs-linux-$(arch_resolve "x86_64" "aarch64")-gnu-v*.zip"
    # CLEAN_INSTALL checks every directory for a mount; node_modules and .next hold 30k+ of them
    rm -rf /opt/cap/node_modules /opt/cap/apps/web/.next
    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "cap" "CapSoftware/Cap" "tarball" "latest" "/opt/cap" "" "cap-v"
    NODE_VERSION="24" NODE_MODULE="$(jq -r '.packageManager' /opt/cap/package.json)" setup_nodejs

    msg_info "Building Cap"
    cd /opt/cap
    $STD bun install --frozen-lockfile
    NEXT_PUBLIC_DOCKER_BUILD=true NEXT_PUBLIC_WEB_URL="$(grep -oP '^WEB_URL=\K.*' /opt/cap_data/.env)" NEXT_TELEMETRY_DISABLED=1 $STD bun run build:web
    cp -r apps/web/.next/static apps/web/.next/standalone/apps/web/.next/
    cp -r apps/web/public apps/web/.next/standalone/apps/web/
    cp -r packages/database/migrations apps/web/.next/standalone/apps/web/
    rm -rf apps/web/.next/cache ~/.bun/install/cache ~/.npm
    msg_ok "Built Cap"

    msg_info "Starting Cap"
    systemctl start cap-rustfs cap-media-server cap-web
    msg_ok "Started Cap"
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
