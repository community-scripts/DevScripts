#!/usr/bin/env bash
_CS_DEFAULT_URL="https://raw.githubusercontent.com/community-scripts/DevScripts/main"
_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../core}/core/build.func"
source "$_cs_boot" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/build.func")

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Marc Went (Dunky13)
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://github.com/beyonders-studio/initiative

APP="Initiative"
var_tags="${var_tags:-productivity;tasks;collaboration}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-8}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"
var_testurl="${var_testurl:-https://github.com/community-scripts/DevScripts/issues/2483}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -f /etc/initiative/server.env || ! -x /usr/bin/initiative-server ]]; then
    msg_error "No Initiative installation found!"
    exit 1
  fi
  if [[ "$(get_os_info id)" != "debian" || "$(get_os_info version)" != "13" ]]; then
    msg_error "Initiative server packages require Debian 13 with Python 3.13."
    exit 1
  fi

  if check_for_gh_release "initiative" "beyonders-studio/initiative" "${var_appversion:-}"; then
    release="$CHECK_UPDATE_RELEASE"
    if [[ ! "$release" =~ ^v?[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
      msg_error "Unsupported Initiative release tag: $release"
      exit 1
    fi
    arch=$(dpkg --print-architecture)
    release_dir=$(mktemp -d /opt/initiative-release.XXXXXX)
    FORCE_UPDATE=1 USE_ORIGINAL_FILENAME=true fetch_and_deploy_gh_release \
      "initiative-package" "beyonders-studio/initiative" "singlefile" "$release" "$release_dir" \
      "initiative-server_${release#v}-*_${arch}.deb"
    FORCE_UPDATE=1 USE_ORIGINAL_FILENAME=true fetch_and_deploy_gh_release \
      "initiative-checksums" "beyonders-studio/initiative" "singlefile" "$release" "$release_dir" \
      "initiative-server-deb-${arch}.sha256"

    msg_info "Verifying Initiative Server Package"
    (cd "$release_dir" && sha256sum --check --strict "initiative-server-deb-${arch}.sha256")
    packages=("$release_dir"/initiative-server_"${release#v}"-*_"${arch}".deb)
    if [[ "${#packages[@]}" != 1 || ! -f "${packages[0]}" ]] ||
      [[ "$(dpkg-deb --field "${packages[0]}" Package)" != "initiative-server" ||
      "$(dpkg-deb --field "${packages[0]}" Architecture)" != "$arch" ]]; then
      msg_error "The Initiative release does not contain one matching native server package."
      exit 1
    fi
    msg_ok "Verified Initiative Server Package"

    msg_info "Stopping Initiative and PostgreSQL for Backup"
    systemctl stop initiative-server postgresql@17-main postgresql
    if ! pg_lsclusters --no-header | awk '$4 != "down" { exit 1 }'; then
      msg_error "PostgreSQL is still running. Initiative was stopped; no package was replaced or database copied."
      exit 1
    fi
    msg_ok "Stopped Initiative and PostgreSQL for Backup"

    # An offline cluster copy includes the roles required by Initiative's RLS.
    backup_dir=$(mktemp -d /opt/initiative-backup.XXXXXX)
    BACKUP_DIR="$backup_dir" create_backup /etc/initiative /var/lib/initiative /etc/postgresql /var/lib/postgresql

    msg_info "Installing Initiative Server Update"
    systemctl start postgresql postgresql@17-main
    DEBIAN_FRONTEND=noninteractive SYSTEMD_OFFLINE=1 $STD apt install -y \
      -o Dpkg::Options::=--force-confold "${packages[0]}"
    # SYSTEMD_OFFLINE also skips the package hook's unit reload.
    systemctl daemon-reload
    systemctl start initiative-server
    msg_ok "Installed Initiative Server Update"

    msg_info "Checking Initiative Readiness"
    if ! $STD curl --fail-with-body --silent --retry 90 --retry-delay 2 \
      --retry-connrefused --retry-all-errors --retry-max-time 180 --max-time 5 \
      --output "$release_dir/ready.json" http://127.0.0.1:8173/api/v1/readyz; then
      msg_error "Initiative readiness request failed. Inspect $release_dir/ready.json and journalctl -u initiative-server."
      exit 1
    fi
    if ! readiness_status=$(jq -ers '
      select(length == 1) | .[0]
      | select(type == "object")
      | select(.checks | type == "object")
      | select(
          (.status == "ok" or .status == "degraded")
          and .checks.database == "ok"
          and .checks.database_system == "ok"
          and .checks.database_provisioning == "ok"
          and (.checks | all(. == "ok" or . == "error"))
          and (if .status == "ok" then (.checks | all(. == "ok"))
               else (.checks | any(. == "error")) end)
        )
      | .status
    ' "$release_dir/ready.json"); then
      msg_error "Initiative returned an invalid or unavailable readiness response. Inspect $release_dir/ready.json."
      exit 1
    fi
    degraded_checks=$(jq -r '.checks | to_entries | map(select(.value != "ok") | .key) | join(", ")' "$release_dir/ready.json")
    # The release helpers track downloads; record installation only after startup succeeds.
    cat <<EOF >"${HOME}/.initiative"
${release#v}
EOF
    rm -rf "$release_dir"
    msg_ok "Initiative Is Ready"
    if [[ "$readiness_status" == "degraded" ]]; then
      msg_warn "Initiative is serving with degraded dependencies: $degraded_checks. Inspect journalctl -u initiative-server."
    fi
    msg_ok "Updated Initiative successfully. Pre-update backup: $backup_dir"
  fi
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}Initiative setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW}Accept the self-signed certificate, then create the first owner account immediately:${CL}"
echo -e "${GATEWAY}${BGN}https://${IP}${CL}"
