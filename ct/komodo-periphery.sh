#!/usr/bin/env bash
_CS_DEFAULT_URL="https://raw.githubusercontent.com/community-scripts/DevScripts/main"
_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../core}/core/build.func"
source "$_cs_boot" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/build.func")

# Copyright (c) 2026 community-scripts ORG
# Author: Sofiane A. (soflane)
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://komo.do/ | https://github.com/moghtech/komodo

APP="Komodo-Periphery"
var_tags="${var_tags:-docker;komodo}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-8}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_unprivileged="${var_unprivileged:-1}"
#var_arm64="${var_arm64:-no}" # unset = ask the user; set yes/no only when verified

export var_komodo_core_address="${var_komodo_core_address:-}"
export var_komodo_server_name="${var_komodo_server_name:-}"
export var_komodo_onboarding_key="${var_komodo_onboarding_key:-}"
export var_komodo_core_public_key="${var_komodo_core_public_key:-}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -x /opt/komodo-periphery/periphery || ! -f /etc/komodo/periphery.config.json ]]; then
    msg_error "No Komodo Periphery installation found!"
    exit 233
  fi

  addon_script=$(curl -fsSL "${COMMUNITY_SCRIPTS_URL}/tools/addon/komodo-periphery.sh")
  type=update bash -c "$addon_script"
  exit
}

if on_pve_host; then
  if is_unattended && [[ -z "$var_komodo_core_address" || -z "$var_komodo_onboarding_key" ]]; then
    msg_error "Supply var_komodo_core_address and var_komodo_onboarding_key before creating the Komodo Periphery LXC."
    exit 1
  fi
  var_komodo_core_address=$(prompt_input_required "Komodo Core URL:" "" 120 "var_komodo_core_address")
  if [[ ! "$var_komodo_core_address" =~ ^https?://[^[:space:]/]+(/[^[:space:]]*)?$ ]]; then
    msg_error "Komodo Periphery requires an HTTP or HTTPS Core URL without whitespace."
    exit 1
  fi
  if [[ -z "$var_komodo_onboarding_key" ]] && ! is_unattended; then
    read -r -s -p "${TAB3}Komodo Server Onboarding Key: " var_komodo_onboarding_key </dev/tty || true
    echo
  fi
  if [[ -z "$var_komodo_onboarding_key" ]]; then
    msg_error "A Komodo Server Onboarding Key is required before creating the LXC."
    exit 1
  fi
fi

start
build_container
description

msg_ok "Komodo Periphery LXC created successfully!"
echo -e "${INFO}Confirm the new server connection in Komodo Core."
echo -e "${INFO}Update the agent inside the LXC with update_komodo_periphery."
