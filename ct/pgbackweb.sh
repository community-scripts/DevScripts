#!/usr/bin/env bash
_CS_DEFAULT_URL="https://raw.githubusercontent.com/community-scripts/DevScripts/main"
_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../core}/core/build.func"
source "$_cs_boot" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/build.func")
# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://github.com/eduardolat/pgbackweb

APP="PG Back Web"
var_tags="${var_tags:-backup;postgresql}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-6}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"
var_testurl="${var_testurl:-https://github.com/community-scripts/DevScripts/issues/2621}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/pgbackweb ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "pgbackweb" "eduardolat/pgbackweb"; then
    msg_info "Stopping PG Back Web"
    systemctl stop pgbackweb
    msg_ok "Stopped PG Back Web"

    setup_go
    fetch_and_deploy_gh_release "task" "go-task/task" "binary"
    fetch_and_deploy_gh_release "sqlc" "sqlc-dev/sqlc" "prebuild" "latest" "/usr/local/bin" "sqlc_*_linux_$(arch_resolve).tar.gz"
    fetch_and_deploy_gh_release "goose" "pressly/goose" "singlefile" "latest" "/usr/local/bin" "goose_linux_$(arch_resolve "x86_64" "arm64")"
    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "pgbackweb" "eduardolat/pgbackweb" "tarball"

    msg_info "Building PG Back Web"
    cd /opt/pgbackweb
    $STD bash ./scripts/set-version.sh "v$(cat ~/.pgbackweb)"
    $STD npm ci
    $STD task build
    rm -rf node_modules
    msg_ok "Built PG Back Web"

    msg_info "Starting PG Back Web"
    systemctl start pgbackweb
    msg_ok "Started PG Back Web"
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
echo -e "${GATEWAY}${BGN}http://${IP}:8085${CL}"
