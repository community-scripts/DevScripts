#!/usr/bin/env bash
_CS_DEFAULT_URL="https://raw.githubusercontent.com/community-scripts/DevScripts/main"
_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../core}/core/build.func"
source "$_cs_boot" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/build.func")
# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://github.com/docling-project/docling-serve

APP="Docling-Serve"
var_tags="${var_tags:-ai;documents;ocr}"
var_cpu="${var_cpu:-4}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-10}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

export var_docling_api_key="${var_docling_api_key:-}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/docling-serve ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "docling-serve" "docling-project/docling-serve"; then
    msg_info "Stopping Docling Serve"
    systemctl stop docling-serve
    msg_ok "Stopped Docling Serve"

    PYTHON_VERSION="3.12" setup_uv

    msg_info "Updating Docling Serve"
    $STD uv pip install --upgrade --python /opt/docling-serve/.venv/bin/python --torch-backend cpu "docling-serve[rapidocr,tesserocr]==${CHECK_UPDATE_RELEASE#v}"
    cat <<EOF >~/.docling-serve
${CHECK_UPDATE_RELEASE#v}
EOF
    msg_ok "Updated Docling Serve"

    msg_info "Updating Docling Models"
    $STD /opt/docling-serve/.venv/bin/docling-tools models download -o /opt/docling-serve_data/models layout tableformer picture_classifier rapidocr
    msg_ok "Updated Docling Models"

    msg_info "Starting Docling Serve"
    systemctl start docling-serve
    msg_ok "Started Docling Serve"
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
echo -e "${GATEWAY}${BGN}http://${IP}:5001${CL}"
echo -e "${INFO}${YW}The API key is DOCLING_SERVE_API_KEY in /opt/docling-serve_data/.env${CL}"
