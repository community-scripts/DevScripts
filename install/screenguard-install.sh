#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://example.invalid/project

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing"
curl -fsSL https://github.com/adambie/screenguard/releases/latest/download/install.sh | bash
msg_ok "Installed"

motd_ssh
customize
cleanup_lxc
