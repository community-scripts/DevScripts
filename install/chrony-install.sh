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

var_ntp_stratum="${var_ntp_stratum:-2}"

msg_info "Installing Chrony"
$STD apt install -y chrony
mkdir -p /etc/systemd/system/chrony.service.d
cat <<EOF >/etc/systemd/system/chrony.service.d/container.conf
[Unit]
ConditionCapability=
ConditionVirtualization=
EOF
cat <<EOF >/etc/default/chrony
DAEMON_OPTS="-F 1 -x"
EOF
systemctl daemon-reload
msg_ok "Installed Chrony"

if [[ "$var_ntp_stratum" == "1" ]]; then
  if [[ -z "${var_gps_device:-}" ]]; then
    read -rp "${TAB3}GPS receiver device [/dev/ttyACM0]: " var_gps_device
  fi
  var_gps_device="${var_gps_device:-/dev/ttyACM0}"
  if [[ ! -e "$var_gps_device" ]]; then
    msg_warn "${var_gps_device} is not present yet; Chrony serves as stratum 2 from the pool, and gpsd starts once the receiver is attached and the container restarted"
  fi

  msg_info "Installing gpsd"
  $STD apt install -y gpsd gpsd-clients
  msg_ok "Installed gpsd"

  msg_info "Configuring Chrony as stratum 1"
  cat <<EOF >/etc/chrony/conf.d/server.conf
refclock SHM 0 refid NMEA offset 0.1 delay 0.2 poll 3 precision 1e-1
refclock SOCK /run/chrony.${var_gps_device##*/}.sock refid PPS precision 1e-7 prefer
allow
EOF
  systemctl restart chrony
  cat <<EOF >/etc/default/gpsd
DEVICES="${var_gps_device}"
GPSD_OPTIONS="-n"
USBAUTO="false"
EOF
  mkdir -p /etc/systemd/system/gpsd.service.d
  cat <<EOF >/etc/systemd/system/gpsd.service.d/device.conf
[Unit]
ConditionPathExists=${var_gps_device}
EOF
  systemctl daemon-reload
  systemctl enable -q gpsd
  systemctl restart gpsd
  msg_ok "Configured Chrony as stratum 1"
else
  if [[ -z "${var_ntp_servers:-}" ]]; then
    read -rp "${TAB3}Upstream NTP servers, space separated [defaults]: " var_ntp_servers
  fi
  if [[ "$var_ntp_stratum" == "2" ]]; then
    var_ntp_servers="${var_ntp_servers:-ntp.time.nl ptbtime1.ptb.de ptbtime2.ptb.de time.nist.gov}"
  else
    var_ntp_servers="${var_ntp_servers:-0.pool.ntp.org 1.pool.ntp.org 2.pool.ntp.org 3.pool.ntp.org}"
  fi

  msg_info "Configuring Chrony as stratum ${var_ntp_stratum}"
  sed -i 's/^pool /#pool /' /etc/chrony/chrony.conf
  cat <<EOF >/etc/chrony/conf.d/server.conf
$(printf "server %s iburst minstratum $((var_ntp_stratum - 1))\n" $var_ntp_servers)
allow
EOF
  systemctl restart chrony
  msg_ok "Configured Chrony as stratum ${var_ntp_stratum}"
fi

motd_ssh
customize
cleanup_lxc
