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

msg_info "Installing Dependencies (PostgreSQL 16, curl, jq, openssl)"
$STD apt-get install -y \
  curl \
  tar \
  gzip \
  ca-certificates \
  jq \
  openssl \
  postgresql \
  postgresql-contrib

# Mark critical packages as manual to safeguard against clean-lxcs autoremove
if command -v apt-mark >/dev/null 2>&1; then
  apt-mark manual curl tar gzip ca-certificates jq openssl postgresql postgresql-contrib >/dev/null 2>&1 || true
fi
msg_ok "Installed Dependencies"

msg_info "Installing Genealogy Family Tree"
$STD bash -c "$(curl -fsSL https://raw.githubusercontent.com/vlevshits/genealogy/main/scripts/install.sh)"
msg_ok "Installed Genealogy Family Tree"

motd_ssh
customize

msg_info "Cleaning up"
$STD apt-get -y autoremove
$STD apt-get -y clean
rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*
msg_ok "Cleaned up"
