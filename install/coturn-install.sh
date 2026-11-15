#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://github.com/coturn/coturn

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt install -y \
  build-essential \
  pkg-config \
  libevent-dev \
  libssl-dev \
  libsqlite3-dev
msg_ok "Installed Dependencies"

fetch_and_deploy_gh_release "coturn" "coturn/coturn" "tarball"

msg_info "Building Coturn"
cd /opt/coturn
$STD ./configure --prefix=/usr/local --turndbdir=/opt/coturn_data --sysconfdir=/etc/coturn --disable-rpath
$STD make -j"$(nproc)"
$STD make install
msg_ok "Built Coturn"

create_self_signed_cert "coturn"

msg_info "Configuring Coturn"
var_coturn_realm="${var_coturn_realm:-$(hostname)}"
var_coturn_secret="${var_coturn_secret:-$(random_password 32)}"
mkdir -p /opt/coturn_data
cat <<EOF >/opt/coturn_data/.env
REALM=${var_coturn_realm}
STATIC_AUTH_SECRET=${var_coturn_secret}
EOF
chmod 600 /opt/coturn_data/.env
cat <<EOF >/etc/turnserver.conf
listening-port=3478
tls-listening-port=5349
# external-ip=<public-ip>/<container-ip>
min-port=49160
max-port=49200
fingerprint
use-auth-secret
static-auth-secret=${var_coturn_secret}
realm=${var_coturn_realm}
cert=/etc/ssl/coturn/coturn.crt
pkey=/etc/ssl/coturn/coturn.key
no-multicast-peers
no-software-attribute
syslog
denied-peer-ip=0.0.0.0-0.255.255.255
denied-peer-ip=10.0.0.0-10.255.255.255
denied-peer-ip=100.64.0.0-100.127.255.255
denied-peer-ip=127.0.0.0-127.255.255.255
denied-peer-ip=169.254.0.0-169.254.255.255
denied-peer-ip=172.16.0.0-172.31.255.255
denied-peer-ip=192.0.0.0-192.0.0.255
denied-peer-ip=192.0.2.0-192.0.2.255
denied-peer-ip=192.88.99.0-192.88.99.255
denied-peer-ip=192.168.0.0-192.168.255.255
denied-peer-ip=198.18.0.0-198.19.255.255
denied-peer-ip=198.51.100.0-198.51.100.255
denied-peer-ip=203.0.113.0-203.0.113.255
denied-peer-ip=240.0.0.0-255.255.255.255
denied-peer-ip=::1
denied-peer-ip=64:ff9b::-64:ff9b::ffff:ffff
denied-peer-ip=::ffff:0.0.0.0-::ffff:255.255.255.255
denied-peer-ip=100::-100::ffff:ffff:ffff:ffff
denied-peer-ip=2001::-2001:1ff:ffff:ffff:ffff:ffff:ffff:ffff
denied-peer-ip=2002::-2002:ffff:ffff:ffff:ffff:ffff:ffff:ffff
denied-peer-ip=fc00::-fdff:ffff:ffff:ffff:ffff:ffff:ffff:ffff
denied-peer-ip=fe80::-febf:ffff:ffff:ffff:ffff:ffff:ffff:ffff
EOF
chmod 600 /etc/turnserver.conf
msg_ok "Configured Coturn"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/coturn.service
[Unit]
Description=Coturn STUN/TURN Server
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/local/bin/turnserver -c /etc/turnserver.conf --pidfile=/run/turnserver.pid
Restart=on-failure
RestartSec=5
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now coturn
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc
