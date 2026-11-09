#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Valentin Levshits (vlevshits)
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://github.com/vlevshits/genealogy

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt install -y \
  curl \
  tar \
  gzip \
  ca-certificates \
  jq \
  openssl
msg_ok "Installed Dependencies"

msg_info "Installing Genealogy Family Tree"
$STD bash -c "$(curl -fsSL https://raw.githubusercontent.com/vlevshits/genealogy/main/scripts/install.sh)"
msg_ok "Installed Genealogy Family Tree"

motd_ssh
customize
cleanup_lxc
