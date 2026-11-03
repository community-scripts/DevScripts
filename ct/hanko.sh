#!/usr/bin/env bash
_CS_DEFAULT_URL="https://raw.githubusercontent.com/community-scripts/DevScripts/main"
_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../core}/core/build.func"
source "$_cs_boot" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/build.func")
# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://github.com/teamhanko/hanko

APP="Hanko"
var_tags="${var_tags:-auth;passkeys;sso}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-512}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"
var_testurl="${var_testurl:-https://github.com/community-scripts/DevScripts/issues/2374}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/hanko ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  # the monorepo tags the backend as backend/vX.Y.Z next to its frontend packages
  if check_for_gh_release "hanko" "teamhanko/hanko" "" "" "backend/"; then
    msg_info "Stopping Hanko"
    systemctl stop hanko
    msg_ok "Stopped Hanko"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "hanko" "teamhanko/hanko" "prebuild" "latest" "/opt/hanko" "hanko_Linux_$(arch_resolve "x86_64" "arm64").tar.gz" "backend/"

    msg_info "Migrating Hanko Database"
    $STD /opt/hanko/hanko migrate up --config /opt/hanko_data/config.yaml
    msg_ok "Migrated Hanko Database"

    msg_info "Starting Hanko"
    systemctl start hanko
    msg_ok "Started Hanko"
    msg_ok "Updated successfully!"
  fi
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW}Access the public API using the following URL:${CL}"
echo -e "${GATEWAY}${BGN}http://${IP}:8000${CL}"
echo -e "${INFO}${YW}Set your app's domain and SMTP server in /opt/hanko_data/config.yaml${CL}"
