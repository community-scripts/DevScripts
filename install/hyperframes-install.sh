#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Estcool9
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://github.com/heygen-com/hyperframes

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

NODE_VERSION="22" NODE_MODULE="hyperframes" setup_nodejs
setup_ffmpeg

if [[ "$(dpkg --print-architecture)" == "arm64" ]]; then
  msg_info "Installing Chromium for ARM64"
  $STD apt install -y chromium
  msg_ok "Installed Chromium for ARM64"
fi

msg_info "Preparing HyperFrames browser"
$STD hyperframes browser ensure
msg_ok "Prepared HyperFrames browser"

mkdir -p /opt/hyperframes_data
$STD hyperframes --version

motd_ssh
customize
cleanup_lxc
