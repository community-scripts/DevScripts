#!/usr/bin/env bash
_CS_DEFAULT_URL="https://raw.githubusercontent.com/community-scripts/DevScripts/main"
_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../core}/core/build.func"
source "$_cs_boot" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/build.func")
# Copyright (c) 2021-2026 community-scripts ORG
# Author: masterde
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://github.com/browseros-ai/BrowserOS

APP="BrowserOS-Neo"
var_tags="${var_tags:-browser;ai;mcp}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-10}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-no}" # GitHub releases ship an amd64 .deb only
var_unprivileged="${var_unprivileged:-1}"

export var_tailscale="${var_tailscale:-}"
export var_ts_authkey="${var_ts_authkey:-}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -f /etc/systemd/system/browseros-neo.service ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "browseros-neo" "browseros-ai/BrowserOS" "" "" "browserclaw/v"; then
    msg_info "Stopping BrowserOS Neo"
    systemctl stop browseros-neo
    msg_ok "Stopped BrowserOS Neo"

    fetch_and_deploy_gh_release "browseros-neo" "browseros-ai/BrowserOS" "binary" "latest" "" "" "browserclaw/v"

    msg_info "Starting BrowserOS Neo"
    systemctl start browseros-neo
    msg_ok "Started BrowserOS Neo"
    msg_ok "Updated successfully!"
  fi
  exit
}

# The container holds logged-in browser sessions, so it always gets a root
# password; with var_pw set the engine also leaves console autologin off.
ROOT_PW_GENERATED=""
if [[ -z "${var_pw:-}" ]] && command -v pveversion >/dev/null 2>&1; then
  ROOT_PW_GENERATED=$(random_password 16)
  var_pw=$(prompt_password "Root password for the BrowserOS Neo container, Enter to generate one" "$ROOT_PW_GENERATED" 120 5)
  export var_pw
fi

# Decided before the container exists: Tailscale needs the TUN device (var_tun).
if [[ -z "$var_tailscale" ]] && command -v pveversion >/dev/null 2>&1; then
  if [[ -n "$var_ts_authkey" ]] || prompt_confirm "Add BrowserOS Neo to your Tailscale tailnet for HTTPS access?" "n" 120; then
    var_tailscale="yes"
  else
    var_tailscale="no"
  fi
fi
[[ "$var_tailscale" == "yes" ]] && export var_tun="yes"

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Open the browser viewer (user: neo) using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:6080${CL}"
echo -e "${INFO}${YW} Connect MCP clients to the following URL with an Authorization: Bearer header:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:9010/mcp${CL}"
TS_NAME=""
[[ "$var_tailscale" == "yes" ]] && TS_NAME=$(pct exec "$CTID" -- bash -c "tailscale status --json 2>/dev/null | jq -r '.Self.DNSName // empty'" | sed 's/\.$//')
if [[ -n "$TS_NAME" ]]; then
  echo -e "${INFO}${YW} On your tailnet:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}https://${TS_NAME}:8443${CL}  (viewer)"
  echo -e "${TAB}${GATEWAY}${BGN}https://${TS_NAME}/mcp${CL}  (MCP)"
fi
echo -e "${INFO}${YW} The viewer password and MCP token are in /opt/browseros-neo_data/.env, show them with:${CL}"
echo -e "${TAB}pct exec ${CTID} -- cat /opt/browseros-neo_data/.env"
if [[ -n "$ROOT_PW_GENERATED" && "${var_pw:-}" == "$ROOT_PW_GENERATED" ]]; then
  # Generated on the host and never stored in the container, so this is the only chance to see it.
  echo -e "${INFO}${YW} Generated root password (save it now):${CL} ${BGN}${ROOT_PW_GENERATED}${CL}"
fi
echo -e "${INFO}${YW} Add it to Claude Code (token from the .env file):${CL}"
if [[ -n "$TS_NAME" ]]; then
  echo -e "${TAB}claude mcp add --transport http browseros-neo https://${TS_NAME}/mcp --header \"Authorization: Bearer <MCP_TOKEN>\""
else
  echo -e "${TAB}claude mcp add --transport http browseros-neo http://${IP}:9010/mcp --header \"Authorization: Bearer <MCP_TOKEN>\""
fi
