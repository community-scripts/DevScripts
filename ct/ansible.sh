#!/usr/bin/env bash
_CS_DEFAULT_URL="https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main"
_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../core}/core/build.func"
source "$_cs_boot" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/build.func")

# Copyright (c) 2021-2026 community-scripts ORG
# Author: proxmox-helper
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/ansible/ansible

APP="Ansible"
var_tags="${var_tags:-automation;ansible}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-8}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_unprivileged="${var_unprivileged:-1}"
#var_arm64="${var_arm64:-no}" # unset: this script has not been tested on arm64

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -x /opt/ansible/ansible/bin/ansible ]]; then
    msg_error "No Ansible Installation Found!"
    exit 1
  fi

  create_backup /etc/ansible /opt/ansible-data
  PYTHON_VERSION="3.13" setup_uv

  # The community package is published on PyPI; GitHub releases track ansible-core.
  msg_info "Updating Ansible"
  export UV_TOOL_DIR="/opt/ansible"
  export UV_TOOL_BIN_DIR="/usr/local/bin"
  $STD uv tool upgrade --python 3.13 ansible
  $STD /usr/local/bin/ansible --version
  msg_ok "Updated Ansible"

  restore_backup
  msg_ok "Updated Ansible successfully!"
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}Ansible setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW}Open the container console and run: ansible localhost -m ansible.builtin.ping${CL}"
echo -e "${INFO}${YW}Ansible inventory: /etc/ansible/hosts; playbooks: /opt/ansible-data/playbooks${CL}"
