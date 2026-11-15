#!/usr/bin/env bash
_CS_DEFAULT_URL="https://raw.githubusercontent.com/community-scripts/DevScripts/main"
_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../core}/core/build.func"
source "$_cs_boot" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/build.func")
# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://github.com/basecamp/fizzy

APP="Fizzy"
var_tags="${var_tags:-kanban;project-management}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-6}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
#var_arm64="${var_arm64:-no}" # unset = ask the user; set yes/no only when verified
var_unprivileged="${var_unprivileged:-1}"
var_testurl="${var_testurl:-https://github.com/community-scripts/DevScripts/issues/2656}"

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

  if [[ ! -d /opt/fizzy ]]; then
    msg_error "No Fizzy Installation Found!"
    exit
  fi

  if check_for_gh_branch "fizzy" "basecamp/fizzy" "main"; then
    msg_info "Stopping Fizzy"
    systemctl stop fizzy
    msg_ok "Stopped Fizzy"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_branch "fizzy" "basecamp/fizzy" "main"

    RUBY_VERSION="$(cat /opt/fizzy/.ruby-version)" RUBY_INSTALL_RAILS="false" setup_ruby

    msg_info "Updating Fizzy"
    rm -rf /opt/fizzy/storage
    ln -s /opt/fizzy_data /opt/fizzy/storage
    cd /opt/fizzy
    export PATH="/root/.rbenv/shims:/root/.rbenv/bin:${PATH}"
    set -a
    source /opt/fizzy_data/.env
    set +a
    $STD bundle install
    $STD bin/rails assets:precompile
    $STD bin/rails db:prepare
    msg_ok "Updated Fizzy"

    msg_info "Starting Fizzy"
    systemctl start fizzy
    msg_ok "Started Fizzy"
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
echo -e "${GATEWAY}${BGN}http://${IP}${CL}"
