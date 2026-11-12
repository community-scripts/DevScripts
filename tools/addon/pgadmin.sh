#!/usr/bin/env bash

# community-scripts ORG | pgAdmin 4 Addon Installer
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://github.com/pgadmin-org/pgadmin4

if command -v curl >/dev/null 2>&1; then
  source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/core.func")
  load_functions
elif command -v wget >/dev/null 2>&1; then
  source <(wget -qO- "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/core.func")
  load_functions
fi
source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/lib/tools.func")
source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/error_handler.func")

color
catch_errors

APP="pgAdmin"
APP_TYPE="addon"

header_info "$APP"
require_debian_like
confirm_not_pve_host
get_lxc_ip

function install_pgadmin() {
  local codename port apache_present="" pgadmin_pass
  codename=$(get_os_info codename)
  if [[ "$(dpkg --print-architecture)" != "amd64" ]]; then
    msg_error "pgAdmin publishes its apt packages for amd64 only."
    exit 238
  fi
  if ! curl -fsI "https://ftp.postgresql.org/pub/pgadmin/pgadmin4/apt/${codename}/dists/pgadmin4/Release" &>/dev/null; then
    msg_error "pgAdmin has no apt repository for ${codename:-this release}."
    exit 238
  fi

  if dpkg-query -W -f='${Status}' apache2 2>/dev/null | grep -q "ok installed"; then
    apache_present=1
    port=$(awk '/^Listen /{print $2; exit}' /etc/apache2/ports.conf)
    port="${port##*:}"
    echo -e "${INFO}${YW}Apache is already installed, pgAdmin is added to it on port ${port}${CL}"
  else
    if [[ -z "${var_pgadmin_port:-}" ]]; then
      var_pgadmin_port=80
      ss -tlnH "sport = :80" | grep -q . && var_pgadmin_port=5050
      var_pgadmin_port=$(prompt_input "pgAdmin port:" "$var_pgadmin_port" 60)
    fi
    port="$var_pgadmin_port"
    if [[ ! "$port" =~ ^[0-9]+$ ]] || ss -tlnH "sport = :${port}" | grep -q .; then
      msg_error "Port ${port} is not free, run again with var_pgadmin_port set to a free port."
      exit 1
    fi
  fi

  if [[ -z "${var_pgadmin_email:-}" ]]; then
    var_pgadmin_email=$(prompt_input "pgAdmin login email:" "admin@example.com" 60)
  fi
  if [[ ! "$var_pgadmin_email" =~ ^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$ ]]; then
    msg_error "${var_pgadmin_email} is not an email address."
    exit 1
  fi

  msg_info "Installing pgAdmin"
  setup_deb822_repo "pgadmin4" \
    "https://www.pgadmin.org/static/packages_pgadmin_org.pub" \
    "https://ftp.postgresql.org/pub/pgadmin/pgadmin4/apt/${codename}" \
    "pgadmin4" \
    "main"
  $STD apt install -y pgadmin4-web
  msg_ok "Installed pgAdmin"

  msg_info "Configuring pgAdmin"
  if [[ -z "$apache_present" && "$port" != "80" ]]; then
    sed -i "s/^Listen 80$/Listen ${port}/" /etc/apache2/ports.conf
  fi
  pgadmin_pass=$(random_password)
  PGADMIN_PLATFORM_TYPE="debian" PGADMIN_SETUP_EMAIL="$var_pgadmin_email" PGADMIN_SETUP_PASSWORD="$pgadmin_pass" $STD /usr/pgadmin4/bin/setup-web.sh --yes
  if ! curl -fsS -o /dev/null --retry 10 --retry-delay 2 --retry-all-errors "http://127.0.0.1:${port}/pgadmin4/misc/ping"; then
    msg_error "pgAdmin does not answer on port ${port}, see /var/log/apache2/error.log and /var/log/pgadmin/pgadmin4.log"
    exit 1
  fi
  msg_ok "Configured pgAdmin"

  echo ""
  msg_ok "pgAdmin is reachable at: ${BL}http://${LOCAL_IP}:${port}/pgadmin4${CL}"
  echo -e "${INFO}${YW}Email:${CL} ${var_pgadmin_email}"
  echo -e "${INFO}${YW}Password:${CL} ${pgadmin_pass}"
  echo -e "${INFO}${YW}The password is not stored anywhere else, change it in pgAdmin under the user menu > Change Password.${CL}"
}

function update_pgadmin() {
  msg_info "Checking for pgAdmin updates"
  $STD apt update
  if apt list --upgradable 2>/dev/null | grep -q "^pgadmin4-web/"; then
    upgrade_packages_with_retry "pgadmin4-web" "pgadmin4-server"
    systemctl restart apache2
    msg_ok "Updated pgAdmin to $(dpkg-query -W -f='${Version}' pgadmin4-web)"
  else
    msg_ok "pgAdmin $(dpkg-query -W -f='${Version}' pgadmin4-web) is already up to date"
  fi
}

function uninstall_pgadmin() {
  msg_info "Uninstalling pgAdmin"
  $STD a2disconf pgadmin4 || true
  $STD apt purge -y pgadmin4-web pgadmin4-server
  $STD apt autoremove --purge -y
  cleanup_old_repo_files "pgadmin4"
  rm -rf /usr/pgadmin4 /var/lib/pgadmin /var/log/pgadmin
  if systemctl is-active --quiet apache2; then
    systemctl reload apache2
  fi
  msg_ok "Uninstalled pgAdmin"
}

if dpkg-query -W -f='${Status}' pgadmin4-web 2>/dev/null | grep -q "ok installed"; then
  if [[ "${type:-}" == "update" ]]; then
    update_pgadmin
    exit 0
  fi
  read -r -p "${TAB}Update (1), Uninstall (2), Cancel (3)? [1/2/3]: " action || action=""
  action="${action//[[:space:]]/}"
  case "$action" in
  1) update_pgadmin ;;
  2) uninstall_pgadmin ;;
  3) msg_warn "No changes made to pgAdmin" ;;
  *) msg_error "Invalid input - no changes made to pgAdmin" ;;
  esac
else
  read -r -p "${TAB}Install pgAdmin? (y/n): " answer || answer=""
  answer="${answer//[[:space:]]/}"
  if [[ "${answer,,}" =~ ^(y|yes)$ ]]; then
    install_pgadmin
  else
    msg_warn "pgAdmin installation skipped"
  fi
fi
