#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://github.com/pydio/cells

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

setup_mariadb
MARIADB_DB_NAME="cells" MARIADB_DB_USER="pydio" MARIADB_DB_CREDS_FILE="/dev/null" setup_mariadb_db

CELLS_VERSION="${var_appversion:-$(get_latest_github_release "pydio/cells")}"
CELLS_VERSION="${CELLS_VERSION#v}"
fetch_and_deploy_from_url "https://download.pydio.com/pub/cells/release/${CELLS_VERSION}/linux-$(arch_resolve)/pydio-cells-${CELLS_VERSION}-linux-$(arch_resolve).zip" /opt/pydio-cells
cat <<EOF >~/.pydio-cells
${CELLS_VERSION}
EOF

msg_info "Configuring Pydio Cells"
var_admin_pass="${var_admin_pass:-$(random_password 16)}"
mkdir -p /opt/pydio-cells_data
cat <<EOF >/opt/pydio-cells_data/.env
ADMIN_USER=admin
ADMIN_PASSWORD=${var_admin_pass}
DB_NAME=cells
DB_USER=pydio
DB_PASSWORD=${MARIADB_DB_PASS}
EOF
chmod 600 /opt/pydio-cells_data/.env
cat <<EOF >/opt/pydio-cells_data/install.yml
frontendlogin: admin
frontendpassword: '${var_admin_pass}'
dbconnectiontype: tcp
dbtcphostname: localhost
dbtcpport: '3306'
dbtcpname: cells
dbtcpuser: pydio
dbtcppassword: '${MARIADB_DB_PASS}'
EOF
CELLS_WORKING_DIR=/opt/pydio-cells_data $STD /opt/pydio-cells/cells configure --yaml /opt/pydio-cells_data/install.yml --bind 0.0.0.0:8080
rm -f /opt/pydio-cells_data/install.yml
msg_ok "Configured Pydio Cells"

msg_info "Creating Pydio Cells Service"
cat <<EOF >/etc/systemd/system/pydio-cells.service
[Unit]
Description=Pydio Cells
Wants=network-online.target
After=network-online.target mariadb.service

[Service]
Type=simple
Environment=CELLS_WORKING_DIR=/opt/pydio-cells_data
ExecStart=/opt/pydio-cells/cells start
Restart=on-failure
LimitNOFILE=65536
KillSignal=INT
TimeoutStopSec=30

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now pydio-cells
msg_ok "Created Pydio Cells Service"

motd_ssh
customize
cleanup_lxc
