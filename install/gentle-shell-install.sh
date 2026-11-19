#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Gentleman-Programming
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://github.com/Gentleman-Programming/gentle-shell

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt install -y git
msg_ok "Installed Dependencies"

NODE_VERSION="22" setup_nodejs

fetch_and_deploy_gh_release "gh" "cli/cli" "binary"

msg_info "Installing gentle-shell (gentle-pi)"
$STD npm install -g gentle-pi
msg_ok "Installed gentle-shell"

cat <<'EOF' >/usr/local/bin/engram
#!/usr/bin/env sh
# Resolves the newest Engram core published by Gentle Shell into ~/.gentle-shell/runtime.
core=$(ls -1d "${HOME:-/root}"/.gentle-shell/runtime/engram-*/engram 2>/dev/null | sort -V | tail -1)
if [ -z "$core" ]; then
  echo "engram: no Gentle Shell published core found." >&2
  echo "engram: start 'gentle-shell' once to publish the Engram core, then retry." >&2
  exit 1
fi
exec "$core" "$@"
EOF
chmod 755 /usr/local/bin/engram

if [[ -n "${var_gh_token:-}" ]]; then
  msg_info "Authenticating GitHub CLI"
  printf '%s' "${var_gh_token}" | gh auth login --with-token
  msg_ok "Authenticated GitHub CLI"
fi

if [[ -n "${var_authorized_key:-}" ]]; then
  msg_info "Installing SSH Access Key"
  mkdir -p /root/.ssh
  chmod 700 /root/.ssh
  if [[ -s /root/.ssh/authorized_keys && -n "$(tail -c 1 /root/.ssh/authorized_keys)" ]]; then
    printf '\n' >> /root/.ssh/authorized_keys
  fi
  printf '%s\n' "${var_authorized_key}" >> /root/.ssh/authorized_keys
  chmod 600 /root/.ssh/authorized_keys
  msg_ok "Installed SSH Access Key"
fi

if [[ "${var_projects_mode:-internal}" == "internal" ]]; then
  mkdir -p /root/projects
fi

motd_ssh
customize
cleanup_lxc
