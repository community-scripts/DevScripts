#!/usr/bin/env bash

# Copyright (c) 2026 community-scripts ORG
# Author: Sofiane A. (soflane)
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://komo.do/ | https://github.com/moghtech/komodo

# shellcheck source=/dev/null
source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

if [[ -z "${var_komodo_addon_script:-}" ]]; then
  msg_error "The Komodo Periphery addon was not supplied by the LXC creator."
  exit 115
fi

msg_info "Preparing Komodo Periphery installer"
mkdir -p /usr/local/lib/komodo-periphery
cat <<EOF >/usr/local/lib/komodo-periphery/addon.sh
$var_komodo_addon_script
EOF
chmod 755 /usr/local/lib/komodo-periphery/addon.sh
msg_ok "Prepared Komodo Periphery installer"

# The CT creation wizard authorizes Docker installation in this new guest.
var_komodo_setup_docker=yes bash /usr/local/lib/komodo-periphery/addon.sh
unset var_komodo_addon_script var_komodo_onboarding_key

motd_ssh
customize
cleanup_lxc
