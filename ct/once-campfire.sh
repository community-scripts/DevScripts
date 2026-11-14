#!/usr/bin/env bash
_CS_DEFAULT_URL="https://raw.githubusercontent.com/community-scripts/DevScripts/main"
_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../core}/core/build.func"
source "$_cs_boot" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/build.func")
# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://github.com/basecamp/once-campfire

APP="Campfire"
var_tags="${var_tags:-chat;communication}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-5}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"
var_testurl="${var_testurl:-https://github.com/community-scripts/DevScripts/issues/2642}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/once-campfire ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "once-campfire" "basecamp/once-campfire"; then
    msg_info "Stopping Campfire"
    systemctl stop once-campfire once-campfire-workers
    msg_ok "Stopped Campfire"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "once-campfire" "basecamp/once-campfire" "tarball"
    RUBY_VERSION="$(cat /opt/once-campfire/.ruby-version)" RUBY_INSTALL_RAILS="false" HOME=/root setup_ruby

    msg_info "Building Campfire"
    export PATH="/root/.rbenv/shims:${PATH}"
    ln -sfn /opt/once-campfire_data/storage /opt/once-campfire/storage
    cd /opt/once-campfire
    $STD bundle config set --local deployment true
    $STD bundle config set --local without "development test"
    $STD bundle install
    rm -rf vendor/bundle/ruby/*/cache vendor/bundle/ruby/*/bundler/gems/*/.git
    RAILS_ENV=production SECRET_KEY_BASE_DUMMY=1 $STD bin/rails assets:precompile
    msg_ok "Built Campfire"

    msg_info "Starting Campfire"
    systemctl start once-campfire once-campfire-workers
    msg_ok "Started Campfire"
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
