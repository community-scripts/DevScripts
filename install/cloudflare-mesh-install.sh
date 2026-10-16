#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: aashishvanand
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-mesh/

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Cloudflare One Client"
setup_deb822_repo \
  "cloudflare-warp" \
  "https://pkg.cloudflareclient.com/pubkey.gpg" \
  "https://pkg.cloudflareclient.com" \
  "$(get_os_info codename)" \
  "main"
$STD apt install -y cloudflare-warp
msg_ok "Installed Cloudflare One Client"

msg_info "Enabling IP Forwarding"
cat <<SYSCTL >/etc/sysctl.d/99-zzz-cloudflare-warp-connector.conf
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
net.ipv6.conf.all.accept_ra = 2
SYSCTL
$STD sysctl -p /etc/sysctl.d/99-zzz-cloudflare-warp-connector.conf
msg_ok "Enabled IP Forwarding"

if [[ -z "${var_mesh_token:-}" ]]; then
  read -r -s -p "${TAB3}Mesh node token from Networking > Mesh > Add node (Enter to skip): " var_mesh_token
  echo
fi
if [[ -n "${var_mesh_token:-}" ]]; then
  msg_info "Connecting Mesh Node"
  for _ in {1..30}; do
    [[ -S /run/cloudflare-warp/warp_service ]] && break
    sleep 1
  done
  $STD warp-cli --accept-tos connector new "$var_mesh_token"
  $STD warp-cli --accept-tos connect
  msg_ok "Connected Mesh Node"
else
  msg_warn "No token provided. Run 'warp-cli --accept-tos connector new <TOKEN> && warp-cli --accept-tos connect' to enroll."
fi

motd_ssh
customize
cleanup_lxc
