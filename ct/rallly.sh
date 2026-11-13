#!/usr/bin/env bash
_CS_DEFAULT_URL="https://raw.githubusercontent.com/community-scripts/DevScripts/main"
_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../core}/core/build.func"
source "$_cs_boot" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/build.func")
# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://github.com/lukevella/rallly

APP="Rallly"
var_tags="${var_tags:-scheduling;polls;calendar}"
var_cpu="${var_cpu:-4}"
var_ram="${var_ram:-6144}"
var_disk="${var_disk:-10}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
#var_arm64="${var_arm64:-no}" # unset = ask the user; set yes/no only when verified
var_unprivileged="${var_unprivileged:-1}"
var_testurl="${var_testurl:-https://github.com/community-scripts/DevScripts/issues/2601}"

export var_admin_email="${var_admin_email:-}"
export var_mail_from="${var_mail_from:-}"
export var_smtp_host="${var_smtp_host:-}"
export var_smtp_port="${var_smtp_port:-}"
export var_smtp_user="${var_smtp_user:-}"
export var_smtp_pass="${var_smtp_pass:-}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/rallly ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "rallly" "lukevella/rallly"; then
    msg_info "Stopping Rallly"
    systemctl stop rallly
    msg_ok "Stopped Rallly"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "rallly" "lukevella/rallly" "tarball"
    NODE_VERSION="24" NODE_MODULE="$(jq -r '.packageManager' /opt/rallly/package.json)" setup_nodejs

    msg_info "Building Rallly"
    cd /opt/rallly
    $STD pnpm install --frozen-lockfile
    NEXT_PUBLIC_SELF_HOSTED=true NEXT_PUBLIC_APP_VERSION="$(cat ~/.rallly)" SKIP_ENV_VALIDATION=1 NEXT_TELEMETRY_DISABLED=1 $STD pnpm build
    cp -r apps/web/.next/static apps/web/.next/standalone/apps/web/.next/
    cp -r apps/web/public apps/web/.next/standalone/apps/web/
    DATABASE_URL="$(sed -n 's/^DATABASE_URL=//p' /opt/rallly_data/.env)" $STD pnpm db:deploy
    rm -rf node_modules apps/*/node_modules packages/*/node_modules apps/web/.next/cache
    msg_ok "Built Rallly"

    msg_info "Starting Rallly"
    systemctl start rallly
    msg_ok "Started Rallly"
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
echo -e "${GATEWAY}${BGN}http://${IP}:3000${CL}"
