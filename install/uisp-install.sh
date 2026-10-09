#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: LuisAngelDesign
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://uisp.com/

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"

color
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt install -y \
  curl \
  ca-certificates
msg_ok "Installed Dependencies"

msg_info "Installing UISP (this can take several minutes)"
$STD bash <(curl -fsSL https://uisp.ui.com/install) --unattended
msg_ok "Installed UISP"

motd_ssh
customize
cleanup_lxc
