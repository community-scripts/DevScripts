#!/usr/bin/env bash
# Copyright (c) 2021-2026 community-scripts ORG
# Author: Rubueno
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://github.com/evan-buss/openbooks

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

fetch_and_deploy_gh_release "openbooks" "evan-buss/openbooks" "singlefile" "latest" "/opt/openbooks" "$(arch_resolve "openbooks_linux" "openbooks_linux_arm")"

if [[ -z "${var_openbooks_persist:-}" ]]; then
  if prompt_confirm "Keep downloaded books in /opt/openbooks/books?" "y" 60; then
    var_openbooks_persist="yes"
  else
    var_openbooks_persist="no"
  fi
fi

msg_info "Configuring OpenBooks"
mkdir -p /opt/openbooks/books
cat <<EOT >/opt/openbooks/.env
IRC_NAME=${var_openbooks_name:-openbooks_$(openssl rand -hex 3)}
OPENBOOKS_ARGS=$([[ "$var_openbooks_persist" == "yes" ]] && echo "--persist" || true)
EOT
msg_ok "Configured OpenBooks"

msg_info "Creating Service"
cat <<EOT >/etc/systemd/system/openbooks.service
[Unit]
Description=OpenBooks
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
Environment=HOME=/opt/openbooks
EnvironmentFile=/opt/openbooks/.env
WorkingDirectory=/opt/openbooks
ExecStart=/opt/openbooks/openbooks server --name \${IRC_NAME} --port 5228 --dir /opt/openbooks/books \$OPENBOOKS_ARGS
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOT
systemctl enable -q --now openbooks
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc
