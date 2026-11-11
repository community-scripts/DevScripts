#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://github.com/zulip/zulip

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

var_zulip_hostname="${var_zulip_hostname:-${LOCAL_IP}}"
var_zulip_email="${var_zulip_email:-zulip-admin@zulip.local}"

fetch_and_deploy_gh_release "zulip" "zulip/zulip" "prebuild" "latest" "/opt/zulip" "zulip-server-*.tar.gz"

msg_info "Installing Zulip"
$STD /opt/zulip/scripts/setup/install --self-signed-cert --hostname="${var_zulip_hostname}" --email="${var_zulip_email}"
rm -f /opt/zulip
sed -i 's/^# *FAKE_EMAIL_DOMAIN = .*/FAKE_EMAIL_DOMAIN = "zulip.local"/' /etc/zulip/settings.py
$STD /home/zulip/deployments/current/scripts/restart-server
msg_ok "Installed Zulip"

msg_info "Saving Organization Link"
cat <<EOF >~/zulip.creds
Zulip URL: https://${var_zulip_hostname}
Organization creation link (single use): $(grep -oE 'https://[^ ]+/new/[A-Za-z0-9]+' /var/log/zulip/install.log | tail -n1)
New link: su zulip -c '/home/zulip/deployments/current/manage.py generate_realm_creation_link'
EOF
chmod 600 ~/zulip.creds
msg_ok "Saved Organization Link"

motd_ssh
customize
cleanup_lxc
