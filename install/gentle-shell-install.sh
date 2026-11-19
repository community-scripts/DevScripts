#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Gentleman-Programming
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://github.com/Gentleman-Programming/gentle-shell

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt install -y git
msg_ok "Installed Dependencies"

NODE_VERSION="22" setup_nodejs

fetch_and_deploy_gh_release "gh" "cli/cli" "binary"

msg_info "Installing gentle-shell (gentle-pi)"
$STD npm install -g gentle-pi
msg_ok "Installed gentle-shell"

if [[ -n "${var_gh_token:-}" ]]; then
  msg_info "Authenticating GitHub CLI"
  printf '%s' "${var_gh_token}" | gh auth login --with-token
  msg_ok "Authenticated GitHub CLI"
fi

if [[ "${var_projects_mode:-internal}" == "internal" ]]; then
  mkdir -p /root/projects
fi

motd_ssh
customize
cleanup_lxc
