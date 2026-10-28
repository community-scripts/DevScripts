#!/usr/bin/env bash

# Copyright (c) 2026 community-scripts ORG
# Author: Sofiane A. (soflane)
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://komo.do/ | https://github.com/moghtech/komodo

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

addon_script=$(curl -fsSL "${COMMUNITY_SCRIPTS_URL}/tools/addon/komodo-periphery.sh")
bash -c "$addon_script"
unset var_komodo_onboarding_key

motd_ssh
customize
cleanup_lxc
