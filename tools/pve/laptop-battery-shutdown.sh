#!/usr/bin/env bash

# Copyright (c) 2026 Christian Sandberg
# Author: Christian Sandberg (chrsandb)
# License: MIT
# https://github.com/chrsandb/proxmox-laptop-poweroff-lowbattery/blob/main/LICENSE
#

set -eEuo pipefail

UPSTREAM_SCRIPT_URL="${PVE_BATTERY_SCRIPT_URL:-https://raw.githubusercontent.com/community-scripts/DevScripts/main/tools/pve/laptop-battery-shutdown.sh}"

# Materialize curl/bash -c and process-substitution launches for installed management.
if [[ ! -f "${BASH_SOURCE[0]:-}" ]]; then
  installer_tmp="$(mktemp)"
  trap 'rm -f "$installer_tmp"' EXIT
  if [[ -n "${BASH_EXECUTION_STRING:-}" ]]; then
    printf '%s\n' "${BASH_EXECUTION_STRING%$'\n'}" >"$installer_tmp"
  else
    curl -fsSL --connect-timeout 10 --max-time 60 "$UPSTREAM_SCRIPT_URL" -o "$installer_tmp"
  fi
  bash -n "$installer_tmp"
  PVE_BATTERY_SCRIPT_URL="$UPSTREAM_SCRIPT_URL" bash "$installer_tmp" "$@"
  exit $?
fi

if command -v curl >/dev/null 2>&1; then
  # shellcheck disable=SC2016 # Variables expand in the telemetry child shell.
  timeout 15s bash -c '
    source <(curl -fsSL --connect-timeout 5 --max-time 10 "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/api/api.func") 2>/dev/null || true
    if declare -f init_tool_telemetry >/dev/null 2>&1; then
      init_tool_telemetry "laptop-battery-shutdown" "pve"
    fi
  ' || true
fi

APP="PVE Laptop Battery Shutdown"
CONFIG_PATH="/etc/default/pve-battery-monitor"
CHECK_PATH="/usr/local/bin/pve-battery-monitor-check"
MANAGER_PATH="/usr/local/bin/pve-battery-monitor-manage"
UPDATE_WRAPPER_PATH="/usr/local/bin/update_pve_battery_monitor"
UNINSTALL_WRAPPER_PATH="/usr/local/bin/uninstall_pve_battery_monitor"
INSTALLER_STORE_DIR="/usr/local/lib/pve-battery-monitor"
INSTALLER_STORE_PATH="${INSTALLER_STORE_DIR}/laptop-battery-shutdown.sh"
STATE_DIR="/var/lib/pve-battery-monitor"
STATE_PATH="${STATE_DIR}/state"
SERVICE_PATH="/etc/systemd/system/pve-battery-monitor.service"
TIMER_PATH="/etc/systemd/system/pve-battery-monitor.timer"

header_info() {
  if [[ -t 1 ]] && [[ -n "${TERM:-}" ]]; then
    clear
  fi
  cat <<"EOF"
    ____  _  ________    __            __  __             __
   / __ \/ |/ / ____/   / /___ _____  / /_/ /_____  ____ / /_
  / /_/ /    / __/_____/ / __ `/ __ \/ __/ __/ __ \/ __ `/ __/
 / ____/ /|  / /__/_____/ / /_/ / /_/ / /_/ /_/ /_/ / /_/ / /_
/_/   /_/ |_/_____/    /_/\__,_/ .___/\__/\__/\____/\__,_/\__/
                              /_/
EOF
}

msg() {
  printf '%s\n' "$1"
}

ensure_root() {
  if [[ ${EUID} -ne 0 ]]; then
    echo "Run as root."
    exit 1
  fi
}

have_battery() {
  compgen -G "/sys/class/power_supply/BAT*" >/dev/null
}

detect_battery() {
  local battery=""
  if [[ -f "$CONFIG_PATH" ]]; then
    battery="$(awk -F= '/^BATTERY_DEVICE=/{gsub(/"/, "", $2); print $2}' "$CONFIG_PATH" 2>/dev/null || true)"
  fi
  if [[ -n "$battery" && -d "/sys/class/power_supply/$battery" ]]; then
    printf '%s\n' "$battery"
    return 0
  fi
  for path in /sys/class/power_supply/BAT*; do
    [[ -d "$path" ]] || continue
    basename "$path"
    return 0
  done
  return 1
}

detect_ac_device() {
  local ac=""
  if [[ -f "$CONFIG_PATH" ]]; then
    ac="$(awk -F= '/^AC_DEVICE=/{gsub(/"/, "", $2); print $2}' "$CONFIG_PATH" 2>/dev/null || true)"
  fi
  if [[ -n "$ac" && -f "/sys/class/power_supply/$ac/online" ]]; then
    printf '%s\n' "$ac"
    return 0
  fi
  if [[ -f /sys/class/power_supply/AC/online ]]; then
    printf 'AC\n'
    return 0
  fi
  for path in /sys/class/power_supply/*/online; do
    [[ -f "$path" ]] || continue
    basename "$(dirname "$path")"
    return 0
  done
  return 1
}

detect_pve_major() {
  local version major
  version="$(pveversion 2>/dev/null | awk -F'/' 'NR==1 {print $2}' | awk -F'-' '{print $1}')"
  major="${version%%.*}"
  printf '%s\n' "${major:-0}"
}

write_config() {
  if [[ -f "$CONFIG_PATH" ]]; then
    return 0
  fi
  cat <<'EOF' >"${staging_dir}/config"
# Generic defaults only. Override devices if autodetection picks the wrong entry.
BATTERY_DEVICE=""
AC_DEVICE=""
LOW_CAPACITY_PERCENT=10
CHECK_INTERVAL_SECONDS=60
DRY_RUN=0
EOF
}

write_check_script() {
  mkdir -p "$(dirname "$CHECK_PATH")" "$STATE_DIR"
  cat <<'EOF' >"${staging_dir}/check"
#!/usr/bin/env bash
set -euo pipefail

CONFIG_PATH="/etc/default/pve-battery-monitor"
STATE_DIR="/var/lib/pve-battery-monitor"
STATE_PATH="${STATE_DIR}/state"
LOG_TAG="pve-battery-monitor"

mkdir -p "$STATE_DIR"
exec 9>"${STATE_DIR}/lock"
flock -n 9 || exit 0

BATTERY_DEVICE=""
AC_DEVICE=""
LOW_CAPACITY_PERCENT=10
CHECK_INTERVAL_SECONDS=60
DRY_RUN=0

if [[ -f "$CONFIG_PATH" ]]; then
  # shellcheck disable=SC1090
  source "$CONFIG_PATH"
fi

if [[ ! "$LOW_CAPACITY_PERCENT" =~ ^[0-9]+$ ]] ||
  [[ ! "$CHECK_INTERVAL_SECONDS" =~ ^[0-9]+$ ]] ||
  [[ ! "$DRY_RUN" =~ ^[01]$ ]]; then
  echo "Invalid battery monitor configuration" >&2
  exit 1
fi
LOW_CAPACITY_PERCENT=$((10#$LOW_CAPACITY_PERCENT))
CHECK_INTERVAL_SECONDS=$((10#$CHECK_INTERVAL_SECONDS))
if ((LOW_CAPACITY_PERCENT < 1 || LOW_CAPACITY_PERCENT > 100 || CHECK_INTERVAL_SECONDS < 1)); then
  echo "Battery threshold must be 1-100 and interval must be positive" >&2
  exit 1
fi

detect_battery() {
  if [[ -n "${BATTERY_DEVICE}" && -d "/sys/class/power_supply/${BATTERY_DEVICE}" ]]; then
    printf '%s\n' "$BATTERY_DEVICE"
    return 0
  fi
  for path in /sys/class/power_supply/BAT*; do
    [[ -d "$path" ]] || continue
    basename "$path"
    return 0
  done
  return 1
}

detect_ac_device() {
  if [[ -n "${AC_DEVICE}" && -f "/sys/class/power_supply/${AC_DEVICE}/online" ]]; then
    printf '%s\n' "$AC_DEVICE"
    return 0
  fi
  if [[ -f /sys/class/power_supply/AC/online ]]; then
    printf 'AC\n'
    return 0
  fi
  for path in /sys/class/power_supply/*/online; do
    [[ -f "$path" ]] || continue
    basename "$(dirname "$path")"
    return 0
  done
  return 1
}

read_uevent_value() {
  local uevent_path="$1"
  local key="$2"
  awk -F= -v search="$key" '$1 == search {sub(/^[^=]*=/, "", $0); print $0; exit}' "$uevent_path"
}

emit_status() {
  local result="$1"
  local action="$2"
  local battery="$3"
  local ac="$4"
  local capacity="$5"
  local status="$6"
  local armed="$7"
  local eta="$8"
  local detail="$9"
  printf 'result=%s action=%s battery=%s ac=%s capacity=%s status=%s armed=%s eta=%s detail=%s\n' \
    "$result" "$action" "$battery" "$ac" "$capacity" "$status" "$armed" "$eta" "$detail"
}

clear_state() {
  rm -f "$STATE_PATH"
}

format_eta() {
  local total_seconds="$1"
  local hours minutes

  if [[ ! "$total_seconds" =~ ^[0-9]+$ ]]; then
    printf 'unknown\n'
    return 0
  fi

  hours=$((total_seconds / 3600))
  minutes=$(((total_seconds % 3600) / 60))
  printf '%02dh%02dm\n' "$hours" "$minutes"
}

estimate_eta_to_shutdown() {
  local ac_online="$1"
  local threshold_percent="$2"
  local energy_now="$3"
  local energy_full="$4"
  local power_now="$5"
  local charge_now="$6"
  local charge_full="$7"
  local current_now="$8"
  local voltage_now="$9"
  local last_energy_now="${10}"
  local last_charge_now="${11}"
  local last_timestamp="${12}"
  local last_ac_online="${13}"
  local current_timestamp="${14}"
  local shutdown_level remaining_level delta_value delta_time eta_seconds discharge_rate mode

  if [[ "$ac_online" != "0" ]]; then
    printf 'on-ac\n'
    return 0
  fi

  if [[ ! "$threshold_percent" =~ ^[0-9]+$ ]]; then
    printf 'unknown\n'
    return 0
  fi

  mode=""
  if [[ "$energy_now" =~ ^[0-9]+$ ]] && [[ "$energy_full" =~ ^[0-9]+$ ]] && ((energy_full > 0)); then
    mode="energy"
    shutdown_level=$((energy_full * threshold_percent / 100))
    remaining_level=$((energy_now - shutdown_level))
  elif [[ "$charge_now" =~ ^[0-9]+$ ]] && [[ "$charge_full" =~ ^[0-9]+$ ]] && ((charge_full > 0)); then
    mode="charge"
    shutdown_level=$((charge_full * threshold_percent / 100))
    remaining_level=$((charge_now - shutdown_level))
  else
    printf 'unknown\n'
    return 0
  fi

  if ((remaining_level <= 0)); then
    printf 'shutdown-now\n'
    return 0
  fi

  if [[ "$mode" == "energy" ]]; then
    discharge_rate=0
    if [[ "$power_now" =~ ^[0-9]+$ ]] && ((power_now > 0)); then
      discharge_rate=$power_now
    elif [[ "$current_now" =~ ^[0-9]+$ ]] && [[ "$voltage_now" =~ ^[0-9]+$ ]] && ((current_now > 0 && voltage_now > 0)); then
      # uA * uV / 1_000_000 = uW
      discharge_rate=$((current_now * voltage_now / 1000000))
    fi

    if ((discharge_rate > 0)); then
      eta_seconds=$((remaining_level * 3600 / discharge_rate))
      format_eta "$eta_seconds"
      return 0
    fi

    if [[ "$last_ac_online" == "0" ]] &&
      [[ "$last_energy_now" =~ ^[0-9]+$ ]] &&
      [[ "$last_timestamp" =~ ^[0-9]+$ ]] &&
      [[ "$current_timestamp" =~ ^[0-9]+$ ]] &&
      ((current_timestamp > last_timestamp)) &&
      ((last_energy_now > energy_now)); then
      delta_value=$((last_energy_now - energy_now))
      delta_time=$((current_timestamp - last_timestamp))
      if ((delta_value > 0 && delta_time > 0)); then
        eta_seconds=$((remaining_level * delta_time / delta_value))
        format_eta "$eta_seconds"
        return 0
      fi
    fi
  fi

  if [[ "$mode" == "charge" ]]; then
    if [[ "$current_now" =~ ^[0-9]+$ ]] && ((current_now > 0)); then
      eta_seconds=$((remaining_level * 3600 / current_now))
      format_eta "$eta_seconds"
      return 0
    fi

    if [[ "$last_ac_online" == "0" ]] &&
      [[ "$last_charge_now" =~ ^[0-9]+$ ]] &&
      [[ "$last_timestamp" =~ ^[0-9]+$ ]] &&
      [[ "$current_timestamp" =~ ^[0-9]+$ ]] &&
      ((current_timestamp > last_timestamp)) &&
      ((last_charge_now > charge_now)); then
      delta_value=$((last_charge_now - charge_now))
      delta_time=$((current_timestamp - last_timestamp))
      if ((delta_value > 0 && delta_time > 0)); then
        eta_seconds=$((remaining_level * delta_time / delta_value))
        format_eta "$eta_seconds"
        return 0
      fi
    fi
  fi

  printf 'unknown\n'
}

save_state() {
  local armed="$1"
  local battery="$2"
  local ac="$3"
  local capacity="$4"
  local energy="$5"
  local charge="$6"
  local timestamp="$7"
  local ac_online="$8"
  local state_tmp
  state_tmp="$(mktemp "${STATE_DIR}/state.XXXXXX")"
  cat <<STATE >"$state_tmp"
ARMED=${armed}
STATE_BOOT_ID="${current_boot_id}"
STATE_BATTERY_DEVICE="${battery}"
STATE_AC_DEVICE="${ac}"
LAST_CAPACITY="${capacity}"
LAST_ENERGY_NOW="${energy}"
LAST_CHARGE_NOW="${charge}"
LAST_TIMESTAMP="${timestamp}"
LAST_AC_ONLINE="${ac_online}"
STATE
  mv -f "$state_tmp" "$STATE_PATH"
}

if ! battery="$(detect_battery)"; then
  emit_status "skip" "clear-state" "missing" "unknown" "unknown" "unknown" "0" "unknown" "no-battery-device"
  logger -t "$LOG_TAG" "No battery device found; clearing state"
  clear_state
  exit 0
fi

if ! ac_device="$(detect_ac_device)"; then
  emit_status "skip" "clear-state" "$battery" "missing" "unknown" "unknown" "0" "unknown" "no-ac-online-device"
  logger -t "$LOG_TAG" "No AC online device found; clearing state"
  clear_state
  exit 0
fi

uevent="/sys/class/power_supply/${battery}/uevent"
if [[ ! -f "$uevent" ]]; then
  emit_status "skip" "clear-state" "$battery" "$ac_device" "unknown" "unknown" "0" "unknown" "missing-uevent"
  logger -t "$LOG_TAG" "Battery uevent file missing for ${battery}; clearing state"
  clear_state
  exit 0
fi

capacity="$(read_uevent_value "$uevent" "POWER_SUPPLY_CAPACITY")"
energy_now="$(read_uevent_value "$uevent" "POWER_SUPPLY_ENERGY_NOW")"
energy_now="${energy_now:-0}"
charge_now="$(read_uevent_value "$uevent" "POWER_SUPPLY_CHARGE_NOW")"
charge_now="${charge_now:-0}"
energy_full="$(read_uevent_value "$uevent" "POWER_SUPPLY_ENERGY_FULL")"
energy_full="${energy_full:-0}"
charge_full="$(read_uevent_value "$uevent" "POWER_SUPPLY_CHARGE_FULL")"
charge_full="${charge_full:-0}"
power_now="$(read_uevent_value "$uevent" "POWER_SUPPLY_POWER_NOW")"
power_now="${power_now:-0}"
current_now="$(read_uevent_value "$uevent" "POWER_SUPPLY_CURRENT_NOW")"
current_now="${current_now:-0}"
voltage_now="$(read_uevent_value "$uevent" "POWER_SUPPLY_VOLTAGE_NOW")"
voltage_now="${voltage_now:-0}"
status="$(read_uevent_value "$uevent" "POWER_SUPPLY_STATUS")"
status="${status:-unknown}"
status_log="${status// /_}"
ac_online="$(cat "/sys/class/power_supply/${ac_device}/online" 2>/dev/null || echo 1)"
current_timestamp="$(date +%s)"

if [[ ! "$capacity" =~ ^[0-9]+$ ]] || ((10#$capacity > 100)); then
  emit_status "skip" "clear-state" "$battery" "$ac_device" "unknown" "$status_log" "0" "unknown" "missing-capacity"
  logger -t "$LOG_TAG" "Battery capacity unavailable for ${battery}; clearing state"
  clear_state
  exit 0
fi
capacity=$((10#$capacity))

ARMED=0
LAST_CAPACITY=-1
LAST_ENERGY_NOW=-1
LAST_CHARGE_NOW=-1
LAST_TIMESTAMP=0
LAST_AC_ONLINE=-1
STATE_BOOT_ID=""
STATE_BATTERY_DEVICE=""
STATE_AC_DEVICE=""
current_boot_id="$(cat /proc/sys/kernel/random/boot_id)"
if [[ -f "$STATE_PATH" ]]; then
  # shellcheck disable=SC1090
  source "$STATE_PATH"
fi

if [[ "$STATE_BOOT_ID" != "$current_boot_id" || "$STATE_BATTERY_DEVICE" != "$battery" || "$STATE_AC_DEVICE" != "$ac_device" ]] ||
  [[ ! "$LAST_TIMESTAMP" =~ ^[0-9]+$ ]] ||
  ((current_timestamp <= LAST_TIMESTAMP || current_timestamp - LAST_TIMESTAMP > CHECK_INTERVAL_SECONDS * 3)); then
  ARMED=0
  LAST_AC_ONLINE=-1
fi

eta_to_shutdown="$(estimate_eta_to_shutdown \
  "$ac_online" \
  "$LOW_CAPACITY_PERCENT" \
  "$energy_now" \
  "$energy_full" \
  "$power_now" \
  "$charge_now" \
  "$charge_full" \
  "$current_now" \
  "$voltage_now" \
  "$LAST_ENERGY_NOW" \
  "$LAST_CHARGE_NOW" \
  "$LAST_TIMESTAMP" \
  "$LAST_AC_ONLINE" \
  "$current_timestamp")"

if [[ "$ac_online" != "0" ]]; then
  emit_status "ok" "none" "$battery" "$ac_device:online" "${capacity}%" "$status_log" "0" "$eta_to_shutdown" "external-power-present"
  if ((ARMED == 1)); then
    logger -t "$LOG_TAG" "AC power restored on ${ac_device}; clearing low-battery armed state"
  fi
  save_state "0" "$battery" "$ac_device" "$capacity" "$energy_now" "$charge_now" "$current_timestamp" "$ac_online"
  exit 0
fi

if ((capacity > LOW_CAPACITY_PERCENT)); then
  emit_status "ok" "none" "$battery" "$ac_device:offline" "${capacity}%" "$status_log" "0" "$eta_to_shutdown" "above-threshold"
  if ((ARMED == 1)); then
    logger -t "$LOG_TAG" "Battery recovered above threshold (${capacity}% > ${LOW_CAPACITY_PERCENT}%); clearing armed state"
  fi
  save_state "0" "$battery" "$ac_device" "$capacity" "$energy_now" "$charge_now" "$current_timestamp" "$ac_online"
  exit 0
fi

if ((ARMED != 1)); then
  emit_status "warn" "arm" "$battery" "$ac_device:offline" "${capacity}%" "$status_log" "1" "$eta_to_shutdown" "first-low-sample"
  logger -t "$LOG_TAG" "Battery low and on battery power (${capacity}%, status=${status}); arming shutdown check"
  save_state "1" "$battery" "$ac_device" "$capacity" "$energy_now" "$charge_now" "$current_timestamp" "$ac_online"
  exit 0
fi

if ((capacity > LAST_CAPACITY)); then
  emit_status "ok" "clear-state" "$battery" "$ac_device:offline" "${capacity}%" "$status_log" "0" "$eta_to_shutdown" "capacity-increased"
  logger -t "$LOG_TAG" "Battery capacity increased (${LAST_CAPACITY}% -> ${capacity}%); clearing armed state"
  save_state "0" "$battery" "$ac_device" "$capacity" "$energy_now" "$charge_now" "$current_timestamp" "$ac_online"
  exit 0
fi

if [[ "$energy_now" =~ ^[0-9]+$ ]] && [[ "$LAST_ENERGY_NOW" =~ ^[0-9]+$ ]] && ((energy_now > LAST_ENERGY_NOW)); then
  emit_status "ok" "clear-state" "$battery" "$ac_device:offline" "${capacity}%" "$status_log" "0" "$eta_to_shutdown" "energy-increased"
  logger -t "$LOG_TAG" "Battery energy increased (${LAST_ENERGY_NOW} -> ${energy_now}); clearing armed state"
  save_state "0" "$battery" "$ac_device" "$capacity" "$energy_now" "$charge_now" "$current_timestamp" "$ac_online"
  exit 0
fi

if [[ "${DRY_RUN}" == "1" ]]; then
  emit_status "crit" "dry-run-shutdown" "$battery" "$ac_device:offline" "${capacity}%" "$status_log" "1" "shutdown-now" "persistent-low-battery"
else
  emit_status "crit" "shutdown" "$battery" "$ac_device:offline" "${capacity}%" "$status_log" "1" "shutdown-now" "persistent-low-battery"
fi
logger -t "$LOG_TAG" "Battery low persisted (${capacity}%, status=${status}, ac=${ac_device}); initiating shutdown"
clear_state

if [[ "${DRY_RUN}" == "1" ]]; then
  logger -t "$LOG_TAG" "DRY_RUN=1 set; shutdown command skipped"
  exit 0
fi

shutdown -h now "Low battery on Proxmox host"
EOF
}

write_installed_script_copy() {
  local source_path=""
  source_path="$(readlink -f "${BASH_SOURCE[0]:-$0}" 2>/dev/null || true)"
  mkdir -p "$INSTALLER_STORE_DIR"
  cp "$source_path" "${staging_dir}/installer"
}

write_management_wrappers() {
  cat <<EOF >"${staging_dir}/manager"
#!/usr/bin/env bash
set -euo pipefail

LOCAL_SCRIPT="${INSTALLER_STORE_PATH}"
export PVE_BATTERY_SCRIPT_URL="${UPSTREAM_SCRIPT_URL}"

if [[ -x "\$LOCAL_SCRIPT" ]]; then
  exec "\$LOCAL_SCRIPT" "\$@"
fi

if command -v curl >/dev/null 2>&1; then
  script_tmp="\$(mktemp)"
  trap 'rm -f "\$script_tmp"' EXIT
  curl -fsSL --connect-timeout 10 --max-time 60 "\$PVE_BATTERY_SCRIPT_URL" -o "\$script_tmp"
  bash -n "\$script_tmp"
  bash "\$script_tmp" "\$@"
  exit \$?
fi

echo "No local management script found and curl is unavailable."
exit 1
EOF

  cat <<EOF >"${staging_dir}/update"
#!/usr/bin/env bash
exec "${MANAGER_PATH}" update "\$@"
EOF

  cat <<EOF >"${staging_dir}/uninstall"
#!/usr/bin/env bash
exec "${MANAGER_PATH}" remove "\$@"
EOF
}

write_units() {
  local interval=60
  if [[ -f "$CONFIG_PATH" ]]; then
    # shellcheck disable=SC1090
    source "$CONFIG_PATH"
    if [[ "${CHECK_INTERVAL_SECONDS:-}" =~ ^[0-9]+$ ]] && ((CHECK_INTERVAL_SECONDS > 0)); then
      interval="$CHECK_INTERVAL_SECONDS"
    fi
  fi

  cat <<EOF >"${staging_dir}/pve-battery-monitor.service"
[Unit]
Description=Check Proxmox host battery level and shut down on persistent low battery
After=multi-user.target

[Service]
Type=simple
ExecStart=${CHECK_PATH}
EOF

  cat <<EOF >"${staging_dir}/pve-battery-monitor.timer"
[Unit]
Description=Run Proxmox host battery monitor every minute

[Timer]
OnBootSec=${interval}s
OnUnitActiveSec=${interval}s
Unit=pve-battery-monitor.service

[Install]
WantedBy=timers.target
EOF
}

validate_environment() {
  local pve_major

  ensure_root
  header_info

  if ! command -v systemctl >/dev/null 2>&1; then
    echo "systemd is required."
    exit 1
  fi

  if ! command -v pveversion >/dev/null 2>&1; then
    echo "This host does not look like Proxmox VE."
    exit 1
  fi

  pve_major="$(detect_pve_major)"
  if [[ ! "$pve_major" =~ ^[0-9]+$ ]] || ((pve_major < 8)); then
    echo "Proxmox VE 8 or newer is required."
    exit 1
  fi

  if ! have_battery; then
    echo "No battery device found under /sys/class/power_supply/BAT*."
    exit 1
  fi

  local ac_device ac_online
  ac_device="$(detect_ac_device || true)"
  if [[ -z "$ac_device" ]] ||
    ! ac_online="$(cat "/sys/class/power_supply/${ac_device}/online" 2>/dev/null)" ||
    [[ ! "$ac_online" =~ ^[01]$ ]]; then
    echo "No readable AC power indicator returning 0 or 1 was found."
    echo "Set AC_DEVICE to the power-supply directory name in ${CONFIG_PATH}, then retry."
    exit 1
  fi
}

atomic_install_file() {
  local source_file="$1" destination="$2" mode="$3" temporary_file
  temporary_file="$(mktemp "$(dirname "$destination")/.pve-battery.XXXXXX")"
  if ! install -m "$mode" "$source_file" "$temporary_file" ||
    ! mv -f "$temporary_file" "$destination"; then
    rm -f "$temporary_file"
    return 1
  fi
}

deploy_monitor() {
  local action_label="$1"
  local battery="$2"
  local ac_device="$3"
  local staging_dir script

  staging_dir="$(mktemp -d)"
  trap 'rm -rf "$staging_dir"' EXIT

  write_config
  write_installed_script_copy
  write_management_wrappers
  write_check_script
  write_units

  for script in installer check manager update uninstall; do
    bash -n "${staging_dir}/${script}"
  done
  if [[ -f "${staging_dir}/config" ]]; then
    bash -n "${staging_dir}/config"
    atomic_install_file "${staging_dir}/config" "$CONFIG_PATH" 0644
  fi
  atomic_install_file "${staging_dir}/installer" "$INSTALLER_STORE_PATH" 0755
  atomic_install_file "${staging_dir}/check" "$CHECK_PATH" 0755
  atomic_install_file "${staging_dir}/manager" "$MANAGER_PATH" 0755
  atomic_install_file "${staging_dir}/update" "$UPDATE_WRAPPER_PATH" 0755
  atomic_install_file "${staging_dir}/uninstall" "$UNINSTALL_WRAPPER_PATH" 0755
  atomic_install_file "${staging_dir}/pve-battery-monitor.service" "$SERVICE_PATH" 0644
  atomic_install_file "${staging_dir}/pve-battery-monitor.timer" "$TIMER_PATH" 0644
  rm -rf "$staging_dir"
  trap - EXIT

  systemctl daemon-reload
  systemctl enable -q --now pve-battery-monitor.timer
  systemctl start pve-battery-monitor.service

  msg ""
  msg "${action_label} ${APP}"
  msg "Detected battery: ${battery:-unknown}"
  msg "Detected AC source: ${ac_device:-unknown}"
  msg "Config: ${CONFIG_PATH}"
  msg "Check script: ${CHECK_PATH}"
  msg "Manager script: ${MANAGER_PATH}"
  msg "Update wrapper: ${UPDATE_WRAPPER_PATH}"
  msg "Uninstall wrapper: ${UNINSTALL_WRAPPER_PATH}"
  msg "Timer: pve-battery-monitor.timer"
  msg ""
  msg "Set DRY_RUN=1 in ${CONFIG_PATH} before testing on production hardware."
}

install_monitor() {
  local battery ac_device
  validate_environment
  battery="$(detect_battery || true)"
  ac_device="$(detect_ac_device || true)"
  deploy_monitor "Installed" "$battery" "$ac_device"
}

update_monitor() {
  local battery ac_device
  if [[ "${PVE_BATTERY_UPDATE_LOCAL:-0}" != "1" ]]; then
    local update_tmp
    update_tmp="$(mktemp)"
    trap 'rm -f "$update_tmp"' EXIT
    curl -fsSL --connect-timeout 10 --max-time 60 "$UPSTREAM_SCRIPT_URL" -o "$update_tmp"
    bash -n "$update_tmp"
    PVE_BATTERY_SCRIPT_URL="$UPSTREAM_SCRIPT_URL" PVE_BATTERY_UPDATE_LOCAL=1 bash "$update_tmp" update
    rm -f "$update_tmp"
    trap - EXIT
    return 0
  fi
  validate_environment
  battery="$(detect_battery || true)"
  ac_device="$(detect_ac_device || true)"
  deploy_monitor "Updated" "$battery" "$ac_device"
}

remove_monitor() {
  ensure_root
  header_info
  systemctl disable -q --now pve-battery-monitor.timer pve-battery-monitor.service 2>/dev/null || true
  rm -f "$SERVICE_PATH" "$TIMER_PATH" "$CHECK_PATH" "$MANAGER_PATH" "$UPDATE_WRAPPER_PATH" "$UNINSTALL_WRAPPER_PATH"
  rm -rf "$STATE_DIR" "$INSTALLER_STORE_DIR"
  systemctl daemon-reload
  msg "Removed ${APP}"
  msg "Config left in place at ${CONFIG_PATH}"
}

status_monitor() {
  local battery="" ac_device="" state="disarmed" capacity="unknown" ac_online="unknown"
  ensure_root
  header_info
  battery="$(detect_battery || true)"
  ac_device="$(detect_ac_device || true)"

  if [[ -n "$battery" && -f "/sys/class/power_supply/${battery}/uevent" ]]; then
    capacity="$(awk -F= '/^POWER_SUPPLY_CAPACITY=/{print $2}' "/sys/class/power_supply/${battery}/uevent" 2>/dev/null || echo unknown)"
  fi
  if [[ -n "$ac_device" && -f "/sys/class/power_supply/${ac_device}/online" ]]; then
    ac_online="$(cat "/sys/class/power_supply/${ac_device}/online" 2>/dev/null || echo unknown)"
  fi
  if [[ -f "$STATE_PATH" ]]; then
    # shellcheck disable=SC1090
    source "$STATE_PATH"
    if [[ "${ARMED:-0}" == "1" ]]; then
      state="armed"
    fi
  fi

  msg "Application: ${APP}"
  msg "Battery: ${battery:-not found}"
  msg "AC source: ${ac_device:-not found}"
  msg "Capacity: ${capacity}"
  msg "AC online: ${ac_online}"
  msg "State: ${state}"
  msg ""
  systemctl --no-pager --full status pve-battery-monitor.timer pve-battery-monitor.service || true
}

choose_action() {
  if command -v whiptail >/dev/null 2>&1; then
    whiptail --backtitle "Proxmox VE Helper Scripts" --title "$APP" --menu "Select an option:" 13 62 4 \
      Install "Install battery shutdown monitor" \
      Update "Refresh installed monitor and wrappers" \
      Remove "Remove battery shutdown monitor" \
      Status "Show current monitor status" 3>&1 1>&2 2>&3 || true
    return 0
  fi

  printf 'Select an option [Install/Update/Remove/Status]: ' >&2
  read -r answer
  printf '%s\n' "$answer"
}

main() {
  local action
  case "${1:-}" in
    install | Install) action="Install" ;;
    update | Update) action="Update" ;;
    remove | Remove | uninstall | Uninstall) action="Remove" ;;
    status | Status) action="Status" ;;
    "") action="$(choose_action)" ;;
    *)
      echo "Usage: $0 [install|update|remove|status]"
      exit 1
      ;;
  esac
  case "$action" in
    Install) install_monitor ;;
    Update) update_monitor ;;
    Remove) remove_monitor ;;
    Status) status_monitor ;;
    *)
      echo "Exiting."
      exit 0
      ;;
  esac
}

main "$@"
