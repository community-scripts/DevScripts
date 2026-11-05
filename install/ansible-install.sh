#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: proxmox-helper
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/ansible/ansible

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Ansible Dependencies"
$STD apt install -y openssh-client git
msg_ok "Installed Ansible Dependencies"

PYTHON_VERSION="3.13" setup_uv

msg_info "Installing Ansible"
export UV_TOOL_DIR="/opt/ansible"
export UV_TOOL_BIN_DIR="/usr/local/bin"
$STD uv tool install --python 3.13 --with-executables-from ansible-core ansible
$STD /usr/local/bin/ansible --version
msg_ok "Installed Ansible"

msg_info "Configuring Ansible"
mkdir -p /etc/ansible /opt/ansible-data/playbooks /opt/ansible-data/roles /opt/ansible-data/collections
chmod 700 /etc/ansible /opt/ansible-data
cat <<'EOF' >/etc/ansible/ansible.cfg
[defaults]
inventory = /etc/ansible/hosts
roles_path = /opt/ansible-data/roles
collections_path = /opt/ansible-data/collections
host_key_checking = True
EOF
cat <<'EOF' >/etc/ansible/hosts
[local]
localhost ansible_connection=local ansible_python_interpreter=/opt/ansible/ansible/bin/python

# Add managed hosts in separate groups, for example:
# [servers]
# server1 ansible_host=192.0.2.10 ansible_user=automation
EOF
chmod 600 /etc/ansible/ansible.cfg /etc/ansible/hosts
msg_ok "Configured Ansible"

msg_info "Verifying Ansible"
$STD /usr/local/bin/ansible localhost -m ansible.builtin.ping
msg_ok "Verified Ansible"

motd_ssh
customize
cleanup_lxc
