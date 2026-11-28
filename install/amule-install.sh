#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Manel (manel)
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://github.com/amule-org/amule

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

fetch_and_deploy_gh_release "amule" "amule-org/amule" "prebuild" "latest" "/opt/amule" "aMule-*-Linux-$(arch_resolve "x64" "arm64")-static.tar.gz"

msg_info "Configuring aMule"
AMULE_PASSWORD=${var_amule_password:-$(random_password)}
EC_PASSWORD=$(random_password)
mkdir -p /root/.aMule /opt/amule_data/{Incoming,Temp}
cat <<EOF >/root/.aMule/amule.conf
[eMule]
Port=4662
UDPPort=4672
IncomingDir=/opt/amule_data/Incoming
TempDir=/opt/amule_data/Temp

[ExternalConnect]
AcceptExternalConnections=1
ECAddress=127.0.0.1
ECPort=4712
ECPassword=$(echo -n "${EC_PASSWORD}" | md5sum | cut -d' ' -f1)

[AmuleApi]
Enabled=1
BindAddress=0.0.0.0
HttpPort=4713
EOF
cat <<EOF >/root/.aMule/allowed-remote-dirs.dat
/opt/amule_data
EOF
$STD /opt/amule/amuleapi --set-admin-pass-stdin <<<"${AMULE_PASSWORD}"
$STD /opt/amule/amulecmd -h 127.0.0.1 -p 4712 -P "${EC_PASSWORD}" -w
ln -sf /opt/amule/amulecmd /usr/local/bin/amulecmd
# The static musl build reads its CA bundle from the Alpine path
ln -sf /etc/ssl/certs/ca-certificates.crt /etc/ssl/cert.pem
cat <<EOF >/opt/amule_data/.env
AMULE_WEB_PASSWORD=${AMULE_PASSWORD}
AMULE_EC_PASSWORD=${EC_PASSWORD}
EOF
chmod 600 /opt/amule_data/.env
msg_ok "Configured aMule"

msg_info "Creating aMule Service"
cat <<EOF >/etc/systemd/system/amuled.service
[Unit]
Description=aMule Daemon
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
Environment=HOME=/root
ExecStart=/opt/amule/amuled
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now amuled
msg_ok "Created aMule Service"

motd_ssh
customize
cleanup_lxc
