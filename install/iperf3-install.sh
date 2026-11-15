#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Leif Davisson (leifdavisson)
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://github.com/esnet/iperf

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

setup_deb_based() {
  msg_info "Installing iPerf3"
  $STD apt install -y iperf3
  msg_ok "Installed iPerf3"

  msg_info "Creating Service"
  cat <<'EOF' >/etc/systemd/system/iperf3.service
[Unit]
Description=iPerf3 Network Bandwidth Server
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=nobody
Group=nogroup
ExecStart=/usr/bin/iperf3 -s
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now iperf3
  msg_ok "Created Service"
}

setup_alpine() {
  msg_info "Installing iPerf3"
  $STD apk add --no-cache iperf3
  msg_ok "Installed iPerf3"

  msg_info "Creating Service"
  cat <<'EOF' >/etc/init.d/iperf3
#!/sbin/openrc-run
name="iPerf3"
description="iPerf3 Network Bandwidth Server"
command="/usr/bin/iperf3"
command_args="-s"
command_user="nobody:nobody"
command_background="yes"
pidfile="/run/iperf3.pid"

depend() {
  need net
  after firewall
}
EOF
  chmod +x /etc/init.d/iperf3
  $STD rc-update add iperf3 default
  $STD rc-service iperf3 start
  msg_ok "Created Service"
}

run_os_setup

motd_ssh
customize
cleanup_lxc
