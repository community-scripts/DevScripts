#!/usr/bin/env bash
# Engine comes from community-scripts/core; this repo only ships the scripts.
# Local checkout wins (COMMUNITY_SCRIPTS_CORE_DIR, else a sibling ../core), so a
# fork/branch of core can be tested without touching this file.
_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../core}/core/build.func"
source "$_cs_boot" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/build.func")
# Copyright (c) 2021-2026 community-scripts ORG
# Author: Jayme Snyder (jaymemaurice)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://www.nautobot.com/ | https://github.com/nautobot/nautobot

APP="Nautobot"
var_tags="${var_tags:-network;automation}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-10}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
#var_arm64="${var_arm64:-no}" # unset = ask the user; set yes/no only when verified
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -x /opt/nautobot/bin/nautobot-server ]]; then
    msg_error "No ${APP} Installation Found!"
    exit 1
  fi

  run_nb() {
    runuser -u nautobot -- env \
      HOME=/opt/nautobot \
      NAUTOBOT_ROOT=/opt/nautobot \
      NAUTOBOT_CONFIG=/opt/nautobot/nautobot_config.py \
      NAUTOBOT_INSTALLATION_METRICS_ENABLED=False \
      "$@"
  }

  BACKUP_DIR="/opt/nautobot.backup"
  create_backup \
    /opt/nautobot/.env \
    /opt/nautobot/nautobot_config.py \
    /opt/nautobot/local_requirements.txt
  # Preserve the last-known-good database dump on a retry after a failed update.
  if [[ ! -f "${BACKUP_DIR}/nautobot.sql.gz" ]]; then
    runuser -u postgres -- pg_dump nautobot | gzip -9 >"${BACKUP_DIR}/nautobot.sql.gz"
  fi

  msg_info "Stopping Nautobot Services"
  systemctl stop nautobot nautobot-worker nautobot-scheduler
  msg_ok "Stopped Nautobot Services"

  msg_info "Updating Nautobot"
  $STD runuser -u nautobot -- /opt/nautobot/bin/pip install --upgrade pip wheel
  # Deliberately remain on Nautobot 3.x. Review upstream migration guidance
  # before crossing a future major-version boundary.
  $STD runuser -u nautobot -- /opt/nautobot/bin/pip install --upgrade --no-binary=pyuwsgi 'nautobot>=3.2,<4'
  if [[ -s /opt/nautobot/local_requirements.txt ]]; then
    $STD runuser -u nautobot -- /opt/nautobot/bin/pip install --upgrade -r /opt/nautobot/local_requirements.txt
  fi
  $STD run_nb /opt/nautobot/bin/nautobot-server post_upgrade
  $STD run_nb /opt/nautobot/bin/nautobot-server check
  $STD run_nb /opt/nautobot/bin/nautobot-server health_check
  msg_ok "Updated Nautobot"

  msg_info "Starting Nautobot Services"
  systemctl start nautobot nautobot-worker nautobot-scheduler
  systemctl restart nginx
  msg_ok "Started Nautobot Services"

  # The backup store is retained if an update fails, but removed after a verified
  # successful update so the next run can capture a fresh last-known-good state.
  rm -rf "$BACKUP_DIR"
  msg_ok "Updated successfully!"
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW}Access it using the following URL:${CL}"
echo -e "${GATEWAY}${BGN}http://${IP}${CL}"
echo -e "${INFO}${YW}HTTPS is also available with a self-signed certificate:${CL} ${BGN}https://${IP}${CL}"
echo -e "${INFO}${YW}Generated credentials:${CL} ${GN}cat /opt/nautobot/.env${CL}"
