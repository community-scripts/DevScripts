#!/usr/bin/env bash
_CS_DEFAULT_URL="https://raw.githubusercontent.com/community-scripts/DevScripts/main"
_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../core}/core/build.func"
source "$_cs_boot" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/build.func")
# Copyright (c) 2021-2026 community-scripts ORG
# Author: Community Scripts contributor
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://github.com/bluesky-social/pds
APP="Bluesky PDS"
var_tags="${var_tags:-social;atproto}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-25}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_unprivileged="${var_unprivileged:-1}"
var_arm64=1
var_testurl="${var_testurl:-https://github.com/community-scripts/DevScripts/issues/2528}"
export var_pds_hostname="${var_pds_hostname:-}"

header_info "$APP"
variables
color
catch_errors
function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if check_for_gh_branch "bluesky-pds" "bluesky-social/atproto" "main"; then
    msg_info "Stopping Bluesky PDS"
    systemctl stop pds
    msg_ok "Stopped Bluesky PDS"
    CLEAN_INSTALL=1 fetch_and_deploy_gh_branch "bluesky-pds" "bluesky-social/atproto" "main"
    NODE_VERSION="24" setup_nodejs
    $STD npm install --global pnpm@12.16.1
    export PUPPETEER_SKIP_DOWNLOAD=true
    cd /opt/bluesky-pds
    $STD pnpm install --frozen-lockfile --filter 'pds-service...' --shamefully-hoist
    $STD pnpm run --recursive --stream --workspace-concurrency 1 --filter 'pds-service...' build --force
    $STD pnpm install --prod --filter 'pds-service...' --shamefully-hoist --frozen-lockfile --prefer-offline --config.confirmModulesPurge=false
    msg_info "Starting Bluesky PDS"
    systemctl start pds
    msg_ok "Started Bluesky PDS"
    msg_ok "Updated Bluesky PDS"
  fi
  if check_for_gh_release "goat" "bluesky-social/goat"; then
    fetch_and_deploy_gh_release "goat" "bluesky-social/goat" "binary"
  fi
  exit
}
start
build_container

description
msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} has been successfully initialized!${CL}"
echo -e "${INFO}${YW}PDS URL:${CL} ${BGN}https://${var_pds_hostname:-<your-domain>}${CL}"
echo -e "${INFO}${YW}Administration:${CL} run ${GN}pdsadmin help${CL} inside the container"
echo -e "${INFO}${YW}Cloudflare Tunnel:${CL} route ${var_pds_hostname:-<your-domain>} to HTTP://<LXC-IP>:3000"
echo -e "${INFO}${YW}No Caddy or public inbound ports are required on this LXC when using Cloudflare Tunnel."
