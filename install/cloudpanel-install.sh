#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: TaiKamilla
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://www.cloudpanel.io/

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

var_db_engine="${var_db_engine:-MARIADB_12.3}"
if [[ ! "$var_db_engine" =~ ^(MARIADB_12\.3|MARIADB_11\.8|MYSQL_8\.4)$ ]]; then
  msg_warn "Unsupported database engine '${var_db_engine}', using MARIADB_12.3"
  var_db_engine="MARIADB_12.3"
fi
var_admin_user="${var_admin_user:-admin}"
var_admin_email="${var_admin_email:-admin@example.com}"
if [[ ! "$var_admin_email" =~ ^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$ ]]; then
  msg_warn "Invalid admin email '${var_admin_email}', using admin@example.com"
  var_admin_email="admin@example.com"
fi
var_admin_pass="${var_admin_pass:-$(random_password 20)}"

confirm_external_installer "https://www.cloudpanel.io/" "https://installer.cloudpanel.io/ce/v2/install.sh"

msg_info "Installing Dependencies"
$STD apt install -y openssh-server wget
msg_ok "Installed Dependencies"

msg_info "Installing CloudPanel (Patience)"
curl_with_retry "https://installer.cloudpanel.io/ce/v2/install.sh" /tmp/cloudpanel-install.sh
if ! sha256sum -c --status <<<"8146dbe0a488e7088b04071b0c34d59aa0ab1fe9dcec382d395fd155c9e6c476  /tmp/cloudpanel-install.sh"; then
  msg_error "The CloudPanel installer does not match the checksum published in its documentation"
  exit 1
fi
# SWAP=false: dphys-swapfile cannot manage swap inside a container
$STD env HOME=/root SWAP=false DB_ENGINE="$var_db_engine" bash /tmp/cloudpanel-install.sh
rm -f /tmp/cloudpanel-install.sh
systemctl disable -q --now chrony
systemctl reset-failed chrony
msg_ok "Installed CloudPanel"

msg_info "Creating CloudPanel Admin"
$STD clpctl user:add --userName="$var_admin_user" --email="$var_admin_email" --firstName="Admin" --lastName="CloudPanel" --password="$var_admin_pass" --role="admin" --timezone="UTC" --status="1"
cat <<EOF >~/cloudpanel.creds
CloudPanel Admin
URL: https://${LOCAL_IP}:8443
Username: ${var_admin_user}
Password: ${var_admin_pass}
EOF
chmod 600 ~/cloudpanel.creds
msg_ok "Created CloudPanel Admin"

motd_ssh
customize
cleanup_lxc
