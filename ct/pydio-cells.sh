#!/usr/bin/env bash
_CS_DEFAULT_URL="https://raw.githubusercontent.com/community-scripts/DevScripts/main"
_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../core}/core/build.func"
source "$_cs_boot" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/build.func")
# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://github.com/pydio/cells

APP="Pydio Cells"
var_tags="${var_tags:-files;sharing;collaboration}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-10}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

export var_admin_pass="${var_admin_pass:-}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -x /opt/pydio-cells/cells ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "pydio-cells" "pydio/cells"; then
    msg_info "Stopping Pydio Cells"
    systemctl stop pydio-cells
    msg_ok "Stopped Pydio Cells"

    CLEAN_INSTALL=1 fetch_and_deploy_from_url "https://download.pydio.com/pub/cells/release/${CHECK_UPDATE_RELEASE#v}/linux-$(arch_resolve)/pydio-cells-${CHECK_UPDATE_RELEASE#v}-linux-$(arch_resolve).zip" /opt/pydio-cells
    cat <<EOF >~/.pydio-cells
${CHECK_UPDATE_RELEASE#v}
EOF

    msg_info "Starting Pydio Cells"
    systemctl start pydio-cells
    msg_ok "Started Pydio Cells"
    msg_ok "Updated successfully!"
  fi
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW}Access it using the following URL:${CL}"
echo -e "${GATEWAY}${BGN}https://${IP}:8080${CL}"
echo -e "${INFO}${YW}Admin login: /opt/pydio-cells_data/.env (inside the container)${CL}"
