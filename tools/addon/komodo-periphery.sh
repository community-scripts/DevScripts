#!/usr/bin/env bash

# Copyright (c) 2026 community-scripts ORG
# Author: Sofiane A. (soflane)
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://komo.do/ | https://github.com/moghtech/komodo

for _cs_file in core/core.func lib/tools.func core/error_handler.func; do
  if [[ -n "${COMMUNITY_SCRIPTS_CORE_DIR:-}" && -f "${COMMUNITY_SCRIPTS_CORE_DIR}/${_cs_file}" ]]; then
    # shellcheck source=/dev/null
    source "${COMMUNITY_SCRIPTS_CORE_DIR}/${_cs_file}"
  else
    # shellcheck source=/dev/null
    source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/${_cs_file}")
  fi
done

APP="Komodo Periphery"
APP_TYPE="addon"
NSAPP="komodo-periphery"
BACKUP_DIR="/opt/komodo-periphery.backup"
INSTALL_PATH="/opt/komodo-periphery"
CONFIG_PATH="/etc/komodo/periphery.config.json"
COMMUNITY_SCRIPTS_URL="${COMMUNITY_SCRIPTS_URL:-https://raw.githubusercontent.com/community-scripts/DevScripts/main}"

load_functions
set -Eeuo pipefail
trap 'error_handler' ERR
header_info

if [[ "$EUID" -ne 0 ]]; then
  msg_error "Run the Komodo Periphery addon as root inside a Docker LXC or VM."
  exit 1
fi
confirm_not_pve_host
require_debian_like
if [[ ! -d /run/systemd/system ]]; then
  msg_error "Komodo Periphery requires a running systemd instance."
  exit 238
fi
case "$(uname -m)" in
x86_64 | aarch64 | arm64) ;;
*)
  msg_error "Komodo Periphery supports x86_64 and aarch64 only."
  exit 238
  ;;
esac
if ! command -v docker &>/dev/null; then
  msg_error "Install Docker first, for example with the Docker LXC script."
  exit 237
fi
ensure_docker
$STD docker info
ensure_dependencies git jq

var_komodo_agent_version="${var_komodo_agent_version:-$(cat "${INSTALL_PATH}/version-policy" 2>/dev/null || echo latest)}"
release="$var_komodo_agent_version"
if [[ "$release" == "latest" ]]; then
  release=$(get_latest_github_release "moghtech/komodo" false)
fi
if [[ ! "$release" =~ ^v?2\.[0-9]+\.[0-9]+$ ]]; then
  msg_error "Choose a stable Komodo v2 release compatible with Core using var_komodo_agent_version."
  exit 1
fi
release="v${release#v}"

function write_update_command() {
  local scripts_url core_url update_file
  printf -v scripts_url '%q' "$COMMUNITY_SCRIPTS_URL"
  printf -v core_url '%q' "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}"
  msg_info "Creating Komodo Periphery update command"
  update_file=$(mktemp /usr/local/bin/.update_komodo_periphery.XXXXXX)
  cat <<EOF >"$update_file"
#!/usr/bin/env bash
set -Eeuo pipefail
export COMMUNITY_SCRIPTS_URL=${scripts_url}
export COMMUNITY_SCRIPTS_CORE_URL=${core_url}
addon_script=\$(curl -fsSL "\${COMMUNITY_SCRIPTS_URL}/tools/addon/komodo-periphery.sh")
type=update bash -c "\$addon_script"
EOF
  chmod 755 "$update_file"
  mv -f "$update_file" /usr/local/bin/update_komodo_periphery
  cat <<EOF >"${INSTALL_PATH}/version-policy"
${var_komodo_agent_version}
EOF
  chmod 600 "${INSTALL_PATH}/version-policy"
  msg_ok "Created Komodo Periphery update command"
}

function update_periphery() {
  if [[ ! -x "${INSTALL_PATH}/periphery" || ! -f "$CONFIG_PATH" ]]; then
    msg_error "No Komodo Periphery installation managed by this addon was found."
    exit 233
  fi

  local update_status staging_dir
  if check_for_gh_release "periphery" "moghtech/komodo" "$release"; then
    create_backup "${INSTALL_PATH}/periphery" "$HOME/.periphery"
    staging_dir=$(mktemp -d "${INSTALL_PATH}/.download.XXXXXX")
    # The release helper caches versions even when the download target is only staging.
    if ! FORCE_UPDATE=1 var_appversion="$release" fetch_and_deploy_gh_release \
      "periphery" "moghtech/komodo" "singlefile" "$release" "$staging_dir" \
      "periphery-$(arch_resolve "x86_64" "aarch64")"; then
      restore_backup
      rm -rf "$staging_dir"
      msg_error "Komodo Periphery download failed. The existing service was kept running."
      exit 1
    fi
    if [[ "$(cat "$HOME/.periphery")" != "${release#v}" ]]; then
      restore_backup
      rm -rf "$staging_dir"
      msg_error "Komodo Periphery download did not match the requested release. Kept the existing agent."
      exit 1
    fi

    msg_info "Replacing Komodo Periphery binary"
    systemctl stop periphery
    if ! command install -m 755 "$staging_dir/periphery" "${INSTALL_PATH}/periphery.new" ||
      ! mv -f "${INSTALL_PATH}/periphery.new" "${INSTALL_PATH}/periphery"; then
      restore_backup
      systemctl start periphery
      rm -rf "$staging_dir"
      msg_error "Could not replace Komodo Periphery. Restored the previous agent."
      exit 1
    fi
    rm -rf "$staging_dir"
    if ! systemctl start periphery || ! sleep 2 || ! systemctl is-active --quiet periphery; then
      systemctl stop periphery
      restore_backup
      systemctl start periphery
      msg_error "Komodo Periphery could not start. Restored the previous binary; check journalctl -u periphery."
      exit 1
    fi
    msg_ok "Replaced Komodo Periphery binary"
    rm -rf "$BACKUP_DIR"
  else
    update_status=$?
    if [[ "$update_status" -ne 1 ]]; then
      msg_error "Could not check Komodo Periphery releases. The existing agent was kept."
      exit "$update_status"
    fi
    systemctl start periphery
    $STD systemctl is-active --quiet periphery
  fi
  write_update_command
  msg_ok "Komodo Periphery update completed"
}

function install_periphery() {
  if [[ -e "$CONFIG_PATH" || -e /etc/komodo/periphery.config.toml || -e /etc/systemd/system/periphery.service ]]; then
    msg_error "An existing Periphery configuration or service was found. Keep it and use its existing updater."
    exit 233
  fi
  var_komodo_core_address=$(prompt_input_required "Komodo Core URL:" "" 120 "var_komodo_core_address")
  if [[ -z "$var_komodo_core_address" || "$var_komodo_core_address" == *[[:space:]]* ]]; then
    msg_error "A reachable Komodo Core v2 URL without whitespace is required."
    exit 1
  fi
  var_komodo_server_name=$(prompt_input_required "Komodo server name:" "$(hostname)" 120 "var_komodo_server_name")
  if [[ -z "${var_komodo_onboarding_key:-}" && -t 0 ]]; then
    read -r -s -p "${TAB3}Komodo Server Onboarding Key: " var_komodo_onboarding_key || true
    echo
  fi
  if [[ -z "${var_komodo_onboarding_key:-}" ]]; then
    msg_error "Supply var_komodo_onboarding_key or enter a Server Onboarding Key interactively."
    exit 1
  fi

  FORCE_UPDATE=1 var_appversion="$release" fetch_and_deploy_gh_release \
    "periphery" "moghtech/komodo" "singlefile" "$release" "$INSTALL_PATH" \
    "periphery-$(arch_resolve "x86_64" "aarch64")"
  if [[ "$(cat "$HOME/.periphery")" != "${release#v}" ]]; then
    msg_error "The downloaded Komodo Periphery release did not match the requested version."
    exit 1
  fi

  msg_info "Configuring Komodo Periphery"
  command install -d -m 700 /etc/komodo /etc/komodo/keys
  local config_file
  config_file=$(mktemp /etc/komodo/.periphery.config.XXXXXX)
  # JSON is an upstream-supported format; jq escapes user-supplied credentials and names.
  jq -n \
    --arg address "$var_komodo_core_address" \
    --arg name "$var_komodo_server_name" \
    --arg key "$var_komodo_onboarding_key" \
    --arg core_key "${var_komodo_core_public_key:-file:/etc/komodo/keys/core.pub}" \
    '{root_directory: "/etc/komodo", core_address: $address, connect_as: $name,
      onboarding_key: $key, core_public_keys: $core_key, server_enabled: false}' >"$config_file"
  chmod 600 "$config_file"
  mv -f "$config_file" "$CONFIG_PATH"
  unset var_komodo_onboarding_key
  msg_ok "Configured Komodo Periphery"

  msg_info "Creating Komodo Periphery service"
  cat <<'EOF' >/etc/systemd/system/periphery.service
[Unit]
Description=Komodo Periphery agent
Documentation=https://komo.do/docs/setup/connect-servers
Wants=network-online.target
After=network-online.target docker.service
Requires=docker.service

[Service]
Type=simple
User=root
Environment=HOME=/root
WorkingDirectory=/etc/komodo
ExecStart=/opt/komodo-periphery/periphery --config-path /etc/komodo/periphery.config.json
Restart=on-failure
RestartSec=5
UMask=0077

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now periphery
  sleep 2
  $STD systemctl is-active --quiet periphery
  msg_ok "Created Komodo Periphery service"
  write_update_command
  msg_ok "Confirm the server is connected in Komodo Core. Check journalctl -u periphery if it is not."
}

case "${type:-}" in
update)
  update_periphery
  ;;
"" | install)
  if [[ -x "${INSTALL_PATH}/periphery" && -f "$CONFIG_PATH" ]]; then
    update_periphery
  else
    install_periphery
  fi
  ;;
*)
  msg_error "Komodo Periphery supports type=install or type=update."
  exit 1
  ;;
esac
