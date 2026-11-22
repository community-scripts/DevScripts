#!/usr/bin/env bash
_CS_DEFAULT_URL="https://raw.githubusercontent.com/community-scripts/DevScripts/main"
_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../core}/core/build.func"
source "$_cs_boot" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/build.func")

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Estcool9
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://github.com/OrcaSlicer/OrcaSlicer

APP="OrcaSlicer MCP"
var_tags="${var_tags:-3d-printing;mcp;automation}"
var_cpu="${var_cpu:-4}"
var_ram="${var_ram:-8192}"
var_disk="${var_disk:-36}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-no}"
var_unprivileged="${var_unprivileged:-1}"
var_nesting="${var_nesting:-0}"
var_testurl="${var_testurl:-https://github.com/community-scripts/DevScripts/issues/2700}"

export var_nextcloud_url="${var_nextcloud_url:-}"
export var_nextcloud_user="${var_nextcloud_user:-}"
export var_nextcloud_password="${var_nextcloud_password:-}"
export var_nextcloud_input_dir="${var_nextcloud_input_dir:-STL}"
export var_nextcloud_output_dir="${var_nextcloud_output_dir:-3MF_PRET_A_IMPRIMER}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -x /opt/orcaslicer/orcaslicer ]]; then
    msg_error "No OrcaSlicer installation found!"
    exit
  fi

  if check_for_gh_release "orcaslicer" "OrcaSlicer/OrcaSlicer"; then
    create_backup /opt/orcaslicer_data/.env
    msg_info "Stopping OrcaSlicer MCP"
    systemctl stop orcaslicer-mcp
    msg_ok "Stopped OrcaSlicer MCP"

    fetch_and_deploy_gh_release "orcaslicer" "OrcaSlicer/OrcaSlicer" "singlefile" "latest" "/opt/orcaslicer" "OrcaSlicer_Linux_AppImage_Ubuntu2404_V*.AppImage"

    msg_info "Extracting OrcaSlicer"
    rm -rf /opt/orcaslicer/rootfs /opt/orcaslicer/profiles
    cd /opt/orcaslicer
    ./orcaslicer --appimage-extract >/dev/null
    mv squashfs-root rootfs
    /opt/orcaslicer/.venv/bin/python /opt/orcaslicer/build_profiles.py "$(cat ~/.orcaslicer)"
    restore_backup
    msg_ok "Extracted OrcaSlicer"

    msg_info "Starting OrcaSlicer MCP"
    systemctl start orcaslicer-mcp
    msg_ok "Started OrcaSlicer MCP"
    msg_ok "Updated successfully!"
  fi
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW}MCP endpoint: http://${IP}:8765/mcp${CL}"
echo -e "${INFO}${YW}Nextcloud configuration: /opt/orcaslicer_data/.env${CL}"
echo -e "${INFO}${YW}Restrict TCP port 8765 to trusted MCP clients in the Proxmox firewall.${CL}"
