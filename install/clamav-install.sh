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

msg_info "Installing ClamAV"
$STD apt install -y \
  clamav \
  clamav-daemon \
  clamav-freshclam
msg_ok "Installed ClamAV"

# clamd refuses to start without signatures, so fetch them once before enabling it.
# The packaged freshclam service holds the database lock, so stop it for the first run.
msg_info "Downloading ClamAV Signatures"
systemctl stop clamav-freshclam
$STD freshclam
systemctl enable -q --now clamav-freshclam
systemctl enable -q --now clamav-daemon
msg_ok "Downloaded ClamAV Signatures"

msg_info "Creating Scan Timer"
mkdir -p /mnt/scan
cat <<EOF >/etc/systemd/system/clamav-scan.service
[Unit]
Description=ClamAV scan of /mnt/scan
After=clamav-daemon.service
Requires=clamav-daemon.service

[Service]
Type=oneshot
Nice=19
IOSchedulingClass=idle
ExecStart=/usr/bin/clamdscan --multiscan --fdpass --infected --log=/var/log/clamav/scan.log /mnt/scan
EOF
cat <<EOF >/etc/systemd/system/clamav-scan.timer
[Unit]
Description=Daily ClamAV scan of /mnt/scan

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
