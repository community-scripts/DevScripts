#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Jan Wiebe Klijnsma (jwklijnsma)
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://www.clamav.net

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

if [[ -z "${var_scan_dir:-}" ]]; then
  var_scan_dir=$(prompt_input "ClamAV folder to scan (inside the container):" "/mnt/scan" 60)
fi
var_scan_dir="${var_scan_dir:-/mnt/scan}"
if [[ "$var_scan_dir" != /* ]]; then
  msg_error "var_scan_dir must be an absolute path, got: ${var_scan_dir}"
  exit 1
fi

if [[ -z "${var_clamd_tcp:-}" ]]; then
  if prompt_confirm "Let other hosts scan files with clamd over TCP port 3310?" "n" 60; then
    var_clamd_tcp="yes"
  else
    var_clamd_tcp="no"
  fi
fi

msg_info "Installing ClamAV"
$STD apt install -y \
  clamav \
  clamav-daemon \
  clamav-freshclam
msg_ok "Installed ClamAV"

# The package rewrites clamd.conf from debconf on upgrade with either TCPSocket or
# LocalSocket, never both, so TCP is added as a second listener on the socket unit.
if [[ "${var_clamd_tcp,,}" == "yes" ]]; then
  msg_info "Configuring clamd TCP Listener"
  mkdir -p /etc/systemd/system/clamav-daemon.socket.d
  cat <<EOF >/etc/systemd/system/clamav-daemon.socket.d/tcp.conf
[Socket]
ListenStream=3310
EOF
  systemctl daemon-reload
  msg_ok "Configured clamd TCP Listener"
fi

# clamd refuses to start without signatures, so fetch them once before enabling it.
# The packaged freshclam service holds the database lock, so stop it for the first run.
msg_info "Downloading ClamAV Signatures"
systemctl stop clamav-freshclam
$STD freshclam
systemctl enable -q --now clamav-freshclam
systemctl restart clamav-daemon.socket
systemctl enable -q --now clamav-daemon
msg_ok "Downloaded ClamAV Signatures"

msg_info "Creating Scan Timer"
mkdir -p "$var_scan_dir"
cat <<EOF >/etc/systemd/system/clamav-scan.service
[Unit]
Description=ClamAV scan of ${var_scan_dir}
After=clamav-daemon.service
Requires=clamav-daemon.service

[Service]
Type=oneshot
Nice=19
IOSchedulingClass=idle
ExecStart=/usr/bin/clamdscan --multiscan --fdpass --infected --log=/var/log/clamav/scan.log "${var_scan_dir}"
EOF
cat <<EOF >/etc/systemd/system/clamav-scan.timer
[Unit]
Description=Daily ClamAV scan of ${var_scan_dir}

[Timer]
OnCalendar=daily
RandomizedDelaySec=1h
Persistent=true

[Install]
WantedBy=timers.target
EOF
cat <<EOF >/etc/logrotate.d/clamav-scan
/var/log/clamav/scan.log {
    weekly
    rotate 8
    compress
    missingok
    notifempty
}
EOF
systemctl enable -q --now clamav-scan.timer
msg_ok "Created Scan Timer"

motd_ssh
customize
cleanup_lxc
