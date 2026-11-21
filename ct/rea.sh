#!/usr/bin/env bash
_CS_DEFAULT_URL="https://raw.githubusercontent.com/community-scripts/DevScripts/main"
_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../core}/core/build.func"
source "$_cs_boot" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/build.func")

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Estcool9
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://github.com/morluto/rea

APP="REA"
var_tags="${var_tags:-reverse-engineering;security;analysis;mcp}"
var_cpu="${var_cpu:-8}"
var_ram="${var_ram:-12288}"
var_disk="${var_disk:-80}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-no}"
var_unprivileged="${var_unprivileged:-1}"
var_nesting="${var_nesting:-1}"
var_keyctl="${var_keyctl:-1}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if ! command -v rea >/dev/null 2>&1 || [[ ! -f /etc/systemd/system/rea-mcp.service ]]; then
    msg_error "No REA MCP installation found!"
    exit 1
  fi

  RESTART_REA=0
  if check_for_gh_release "ghidra" "NationalSecurityAgency/ghidra"; then
    msg_info "Updating Ghidra"
    fetch_and_deploy_gh_release "ghidra" "NationalSecurityAgency/ghidra" "prebuild" "latest" "/opt/ghidra" "ghidra_*_PUBLIC_*.zip"
    msg_ok "Updated Ghidra"
    RESTART_REA=1
  fi

  if check_for_gh_release "rea-agents" "morluto/rea"; then
    msg_info "Updating REA"
    $STD npm install --global --allow-scripts=frida rea-agents@latest
    REA_PACKAGE_DIR="$(npm root -g)/rea-agents"
    node -p "require(process.argv[1]).version" "$REA_PACKAGE_DIR/package.json" > "$HOME/.rea-agents"
    msg_ok "Updated REA"
    RESTART_REA=1
  fi

  if [[ "$RESTART_REA" == "1" ]]; then
    systemctl restart rea-mcp
    systemctl is-active --quiet rea-mcp
    msg_ok "Restarted REA MCP"
  fi
  msg_ok "Update completed!"
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW}MCP endpoint (restrict access to a trusted MCP gateway):${CL}"
echo -e "${GATEWAY}${BGN}http://${IP}:8765/mcp${CL}"
