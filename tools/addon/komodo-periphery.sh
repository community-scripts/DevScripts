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
export APP_TYPE="addon"
NSAPP="komodo-periphery"
BACKUP_DIR="/opt/${NSAPP}.backup"
INSTALL_PATH="/opt/komodo-periphery"
CONFIG_PATH="/etc/komodo/periphery.config.json"
COMMUNITY_SCRIPTS_URL="${COMMUNITY_SCRIPTS_URL:-https://raw.githubusercontent.com/community-scripts/DevScripts/main}"

load_functions
catch_errors
header_info "$APP"

root_check
if on_pve_host; then
  msg_error "Run the Komodo Periphery addon inside an LXC or VM, not on the Proxmox VE host."
  exit 232
fi
require_debian_like
if [[ ! -d /run/systemd/system ]]; then
  msg_error "Komodo Periphery requires a running systemd instance."
  exit 238
fi
arch_check

case "${type:-install}" in
install | update) ;;
*)
  msg_error "Komodo Periphery supports type=install or type=update."
  exit 1
  ;;
esac

if [[ -x "${INSTALL_PATH}/periphery" && -f "$CONFIG_PATH" && -f /etc/systemd/system/periphery.service ]] &&
  grep -qxF "ExecStart=${INSTALL_PATH}/periphery --config-path ${CONFIG_PATH}" /etc/systemd/system/periphery.service; then
  type=update
elif [[ "${type:-}" == "update" || -e "$INSTALL_PATH" || -e "$CONFIG_PATH" ||
  -e /etc/komodo/periphery.config.toml || -e /etc/komodo/keys/periphery.key ||
  -e /etc/systemd/system/periphery.service ]]; then
  msg_error "Komodo Periphery installation is missing, incomplete or managed by another installer."
  exit 233
else
  type=install
fi

if [[ "$type" == "install" ]]; then
  if is_unattended && [[ -z "${var_komodo_core_address:-}" || -z "${var_komodo_onboarding_key:-}" ]]; then
    msg_error "Supply var_komodo_core_address and var_komodo_onboarding_key for unattended Komodo Periphery installation."
    exit 1
  fi
  var_komodo_core_address=$(prompt_input_required "Komodo Core URL:" "" 120 "var_komodo_core_address")
  if [[ ! "$var_komodo_core_address" =~ ^https?://[^[:space:]/]+(/[^[:space:]]*)?$ ]]; then
    msg_error "Komodo Periphery requires an HTTP or HTTPS Core URL without whitespace."
    exit 1
  fi
  var_komodo_server_name=$(prompt_input_required "Komodo server name:" "$(hostname)" 120 "var_komodo_server_name")
  if [[ -z "${var_komodo_onboarding_key:-}" ]] && ! is_unattended; then
    read -r -s -p "${TAB3}Komodo Server Onboarding Key: " var_komodo_onboarding_key </dev/tty || true
    echo
  fi
  if [[ -z "${var_komodo_onboarding_key:-}" ]]; then
    msg_error "Supply var_komodo_onboarding_key or enter a Komodo Server Onboarding Key interactively."
    exit 1
  fi
fi

# A new LXC runs its installer headlessly, after the host creation wizard.
if [[ "$type" == "install" && "${var_komodo_setup_docker:-no}" == "yes" ]]; then
  setup_docker
else
  ensure_docker
fi
$STD docker info
ensure_dependencies git jq

if [[ "$type" == "update" ]]; then
  if check_for_gh_release "periphery" "moghtech/komodo"; then
    create_backup "${INSTALL_PATH}/periphery" "$HOME/.periphery"
    version_file_existed=no
    [[ -f "$HOME/.periphery" ]] && version_file_existed=yes
    staging_dir=$(mktemp -d "${INSTALL_PATH}/.download.XXXXXX")
    update_failed=0
    service_stopped=no
    # The helper writes the release cache even when its target is only staging.
    if FORCE_UPDATE=1 var_appversion="$CHECK_UPDATE_RELEASE" fetch_and_deploy_gh_release \
      "periphery" "moghtech/komodo" "singlefile" "$CHECK_UPDATE_RELEASE" "$staging_dir" \
      "periphery-$(arch_resolve "x86_64" "aarch64")" &&
      [[ -s "$staging_dir/periphery" && -x "$staging_dir/periphery" && -f "$HOME/.periphery" ]] &&
      [[ "$(<"$HOME/.periphery")" == "${CHECK_UPDATE_RELEASE#v}" ]] && chmod 755 "$staging_dir/periphery"; then
      msg_info "Replacing Komodo Periphery binary"
      if systemctl stop periphery; then
        service_stopped=yes
        if ! mv -f "$staging_dir/periphery" "${INSTALL_PATH}/periphery" ||
          ! systemctl start periphery || ! sleep 2 || ! systemctl is-active --quiet periphery; then
          msg_error "Could not replace or start Komodo Periphery."
          update_failed=1
        else
          msg_ok "Replaced Komodo Periphery binary"
        fi
      else
        msg_error "Could not stop Komodo Periphery."
        update_failed=1
      fi
    else
      update_failed=1
    fi
    rm -rf "$staging_dir"
    if [[ "$update_failed" == "1" ]]; then
      if [[ "$service_stopped" == "yes" ]]; then
        systemctl stop periphery || true
      fi
      restore_backup
      [[ "$version_file_existed" == "yes" ]] || rm -f "$HOME/.periphery"
      if [[ "$service_stopped" == "yes" ]]; then
        systemctl start periphery || msg_warn "Could not restart the previous Komodo Periphery agent."
      fi
      msg_error "Komodo Periphery update failed; restored the previous agent. Check journalctl -u periphery."
      exit 1
    fi
    rm -rf "$BACKUP_DIR"
  else
    update_status=$?
    if [[ "$update_status" -ne 1 ]]; then
      msg_error "Could not check Komodo Periphery releases."
      exit "$update_status"
    fi
  fi
else
  fetch_and_deploy_gh_release "periphery" "moghtech/komodo" "singlefile" "latest" "$INSTALL_PATH" \
    "periphery-$(arch_resolve "x86_64" "aarch64")"

  msg_info "Configuring Komodo Periphery"
  command install -d -m 700 /etc/komodo /etc/komodo/keys
  config_file=$(mktemp /etc/komodo/.periphery.config.XXXXXX)
  # JSON is supported upstream; jq escapes names and credentials safely.
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
fi

msg_info "Creating Komodo Periphery update command"
printf -v scripts_url '%q' "$COMMUNITY_SCRIPTS_URL"
printf -v core_url '%q' "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}"
update_file=$(mktemp /usr/local/bin/.update_komodo_periphery.XXXXXX)
cat <<EOF >"$update_file"
#!/usr/bin/env bash
set -Eeuo pipefail
export COMMUNITY_SCRIPTS_URL=${scripts_url}
export COMMUNITY_SCRIPTS_CORE_URL=${core_url}
if [[ -f /usr/local/lib/komodo-periphery/addon.sh ]]; then
  type=update bash /usr/local/lib/komodo-periphery/addon.sh
else
  addon_script=\$(curl -fsSL "\$COMMUNITY_SCRIPTS_URL/tools/addon/komodo-periphery.sh")
  type=update bash -c "\$addon_script"
fi
EOF
chmod 755 "$update_file"
mv -f "$update_file" /usr/local/bin/update_komodo_periphery
rm -f "${INSTALL_PATH}/version-policy"
msg_ok "Created Komodo Periphery update command"
msg_ok "Komodo Periphery setup completed"
echo -e "${INFO}Confirm the server connection in Komodo Core; check journalctl -u periphery if needed."
