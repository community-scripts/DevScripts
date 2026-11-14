#!/usr/bin/env bash
_CS_DEFAULT_URL="https://raw.githubusercontent.com/community-scripts/DevScripts/main"
_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../core}/core/build.func"
source "$_cs_boot" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/build.func")
# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://github.com/supertokens/supertokens-core

APP="SuperTokens"
var_tags="${var_tags:-auth;sso}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

export var_api_key="${var_api_key:-}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/supertokens ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "supertokens" "supertokens/supertokens-core"; then
    msg_info "Stopping SuperTokens"
    systemctl stop supertokens
    msg_ok "Stopped SuperTokens"

    CLEAN_INSTALL=1 fetch_and_deploy_from_url "https://api.supertokens.com/0/app/download?pluginName=postgresql&os=$(arch_resolve "linux" "linux-arm")&mode=PRODUCTION&binary=FREE&targetCore=${CHECK_UPDATE_RELEASE#v}" /opt/supertokens

    msg_info "Downloading SuperTokens Dependencies"
    chmod +x /opt/supertokens/jre/bin/* /opt/supertokens/jre/lib/jspawnhelper
    cd /opt/supertokens
    $STD ./jre/bin/java -classpath "./downloader/*" io.supertokens.downloader.Main
    msg_ok "Downloaded SuperTokens Dependencies"
    cat <<EOF >~/.supertokens
${CHECK_UPDATE_RELEASE#v}
EOF

    msg_info "Starting SuperTokens"
    systemctl start supertokens
    msg_ok "Started SuperTokens"
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
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:3567/hello${CL}"
echo -e "${INFO}${YW}API key: /opt/supertokens_data/.env (inside the container)${CL}"
