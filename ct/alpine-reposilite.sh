#!/usr/bin/env bash
_CS_DEFAULT_URL="https://raw.githubusercontent.com/community-scripts/DevScripts/main"
_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../core}/core/build.func"
source "$_cs_boot" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/build.func")

# Copyright (c) 2026
# Author: hwajin-me
# License: MIT
# Source: https://reposilite.com/

APP="Alpine-Reposilite"
var_tags="${var_tags:-alpine;maven;repository}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-8}"
var_os="${var_os:-alpine}"
var_version="${var_version:-3.24}"
var_unprivileged="${var_unprivileged:-1}"
var_nesting="${var_nesting:-0}"
# ARM64 has not been tested; Core asks before attempting it.
#var_arm64="${var_arm64:-no}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  [[ -f /opt/reposilite/reposilite.jar && -f /etc/init.d/reposilite ]] || {
    msg_error "No Reposilite installation found"
    exit 1
  }
  if check_for_gh_release "reposilite" "dzikoysk/reposilite"; then
    RELEASE="$CHECK_UPDATE_RELEASE"
    [[ "$RELEASE" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { msg_error "Invalid Reposilite release"; exit 1; }
    URL="https://maven.reposilite.com/releases/com/reposilite/reposilite/${RELEASE}/reposilite-${RELEASE}-all.jar"
    curl_with_retry "$URL" /opt/reposilite/reposilite.jar.new
    CHECKSUM="$(curl_with_retry "${URL}.sha256")"
    [[ "$CHECKSUM" =~ ^[[:xdigit:]]{64}$ ]] || { msg_error "Invalid Reposilite checksum"; exit 1; }
    msg_info "Verifying Reposilite download"
    $STD sha256sum -c - <<<"$CHECKSUM  /opt/reposilite/reposilite.jar.new"
    msg_ok "Verified Reposilite download"

    # Keep rollback files outside the application and data directories.
    BACKUP_DIR="/opt/reposilite-backups/$(date +%Y%m%d-%H%M%S)"
    create_backup /opt/reposilite/reposilite.jar /root/.reposilite
    msg_info "Updating Reposilite"
    $STD rc-service reposilite stop
    mv /opt/reposilite/reposilite.jar.new /opt/reposilite/reposilite.jar
    $STD rc-service reposilite start
    READY=no
    for ((i=0; i<60; i++)); do
      if curl -fsS --max-time 2 http://127.0.0.1:8080/ >/dev/null 2>&1; then READY=yes; break; fi
      sleep 2
    done
    if [[ "$READY" != yes ]]; then
      $STD rc-service reposilite stop || true
      restore_backup
      msg_error "Reposilite failed to start. Previous JAR restored; check logs and database compatibility before restarting."
      exit 1
    fi
    cat >/root/.reposilite <<EOF
${RELEASE}
EOF
    msg_ok "Updated Reposilite to ${RELEASE}"
  fi
  exit 0
}

start
build_container
description
msg_ok "Reposilite installation completed"
echo -e "${INFO}${YW}URL: http://${IP}:8080${CL}"
echo -e "${INFO}${YW}Initial manager token: admin. Secret: /etc/conf.d/reposilite inside the container.${CL}"
