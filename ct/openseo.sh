#!/usr/bin/env bash
_CS_DEFAULT_URL="https://raw.githubusercontent.com/community-scripts/DevScripts/main"
_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../core}/core/build.func"
source "$_cs_boot" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/build.func")
# Copyright (c) 2021-2026 community-scripts ORG
# Author: Brandon Visca (visbran)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/every-app/open-seo

APP="OpenSEO"
var_tags="${var_tags:-seo;analytics;marketing}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-10}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
#var_arm64="${var_arm64:-no}" # unset = ask the user; set yes/no only when verified
var_unprivileged="${var_unprivileged:-1}"
var_testurl="${var_testurl:-https://github.com/community-scripts/DevScripts/issues/2423}"
export var_dataforseo_api_key="${var_dataforseo_api_key:-}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/openseo ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "openseo" "every-app/open-seo"; then
    msg_info "Stopping OpenSEO"
    systemctl stop openseo
    msg_ok "Stopped OpenSEO"

    create_backup /opt/openseo/.env /opt/openseo/.wrangler

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "openseo" "every-app/open-seo" "tarball"

    restore_backup

    PNPM_VERSION=$(sed -n 's/.*"packageManager": "pnpm@\([^"+]*\).*/\1/p' /opt/openseo/package.json)
    NODE_VERSION="22" NODE_MODULE="pnpm@${PNPM_VERSION:-10.30.1}" setup_nodejs

    msg_info "Building OpenSEO"
    cd /opt/openseo
    $STD pnpm install --frozen-lockfile
    # The Cloudflare vite plugin serializes the whole process env into .dev.vars; run with a clean env so it only sees /opt/openseo/.env
    $STD env -i PATH="$PATH" HOME=/root pnpm run db:migrate:local
    $STD env -i PATH="$PATH" HOME=/root pnpm run build
    msg_ok "Built OpenSEO"

    msg_info "Starting OpenSEO"
    systemctl start openseo
    msg_ok "Started OpenSEO"
    msg_ok "Updated successfully!"
  fi
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:3001${CL}"
