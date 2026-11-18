#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Jan Wiebe Klijnsma (jwklijnsma)
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://chrony-project.org/

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

if [[ -z "${var_gps_device:-}" ]]; then
  read -rp "${TAB3}GPS receiver device [/dev/ttyACM0]: " var_gps_device
fi
var_gps_device="${var_gps_device:-/dev/ttyACM0}"
if [[ ! -e "$var_gps_device" ]]; then
  msg_warn "${var_gps_device} is not present yet; Chrony serves as stratum 2 from the pool until the GPS receiver is attached"
fi

msg_info "Installing Chrony and gpsd"
$STD apt install -y \
  chrony \
  gpsd \
  gpsd-clients
msg_ok "Installed Chrony and gpsd"

msg_info "Configuring Chrony"
cat <<EOF >/etc/chrony/conf.d/gps.conf
refclock SHM 0 refid NMEA offset 0.1 delay 0.2 poll 3 precision 1e-1
refclock SOCK /run/chrony.${var_gps_device##*/}.sock refid PPS precision 1e-7 prefer
allow
EOF
cat <<EOF >/etc/default/chrony
DAEMON_OPTS="-F 1 -x"
EOF
systemctl restart chrony
msg_ok "Configured Chrony"

msg_info "Configuring gpsd"
cat <<EOF >/etc/default/gpsd
DEVICES="${var_gps_device}"
GPSD_OPTIONS="-n"
USBAUTO="false"
EOF
systemctl enable -q gpsd
systemctl restart gpsd
msg_ok "Configured gpsd"

motd_ssh
customize
cleanup_lxc
