#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Filan-glitch
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://sli.dev/

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

NODE_VERSION="24" setup_nodejs

msg_info "Installing Slidev"
cd /opt
$STD npx --yes create-slidev@latest slidev </dev/null
cd /opt/slidev
$STD npm install "@slidev/cli@${var_appversion:-latest}"
cat <<EOF >~/.slidev
$(node -p "require('/opt/slidev/node_modules/@slidev/cli/package.json').version")
EOF
msg_ok "Installed Slidev"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/slidev.service
[Unit]
Description=Slidev
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=/opt/slidev
ExecStart=/opt/slidev/node_modules/.bin/slidev slides.md --remote --port 3030
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now slidev
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc
