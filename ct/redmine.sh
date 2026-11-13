#!/usr/bin/env bash
_CS_DEFAULT_URL="https://raw.githubusercontent.com/community-scripts/DevScripts/main"
_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../core}/core/build.func"
source "$_cs_boot" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/build.func")
# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://github.com/redmine/redmine

APP="Redmine"
var_tags="${var_tags:-project-management;issue-tracker}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
#var_arm64="${var_arm64:-no}" # unset = ask the user; set yes/no only when verified
var_unprivileged="${var_unprivileged:-1}"

export var_admin_pass="${var_admin_pass:-}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/redmine ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_tag "redmine" "redmine/redmine"; then
    msg_info "Stopping Redmine"
    systemctl stop redmine
    msg_ok "Stopped Redmine"

    RUBY_INSTALL_RAILS="false" setup_ruby
    CLEAN_INSTALL=1 CLEAN_INSTALL_KEEP="Gemfile.local config/database.yml config/configuration.yml config/initializers/secret_token.rb plugins themes" fetch_and_deploy_gh_tag "redmine" "redmine/redmine"

    msg_info "Updating Redmine"
    cd /opt/redmine
    export PATH="/root/.rbenv/shims:/root/.rbenv/bin:$PATH"
    $STD bundle config set --local without 'development test'
    $STD bundle install
    RAILS_ENV=production $STD bundle exec rake db:migrate
    RAILS_ENV=production $STD bundle exec rake redmine:plugins:migrate
    RAILS_ENV=production $STD bundle exec rake assets:precompile
    msg_ok "Updated Redmine"

    msg_info "Starting Redmine"
    systemctl start redmine
    msg_ok "Started Redmine"
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
echo -e "${INFO}${YW}Admin login: /opt/redmine_data/.env (inside the container)${CL}"
