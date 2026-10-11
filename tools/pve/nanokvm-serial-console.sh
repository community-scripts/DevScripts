#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Gleb Pesin (dormancygrace)
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://github.com/dormancygrace/NanoKVM-OS
#
# A login on the USB serial port of a NanoKVM running NanoKVM OS, plugged into
# a Proxmox VE or Proxmox Backup Server host, so the host stays reachable from
# the NanoKVM's browser terminal when its network is gone. NanoKVM OS's USB
# serial function is a CDC ACM device (USB 3346:1009, /dev/ttyACMn); one udev
# rule bound to its serial number starts serial-getty@<port> whenever the port
# appears. (The stock Sipeed firmware has no USB serial function.)
# The change is recorded with backups under /var/backups/nanokvm-serial-console
# and reverted by undo.
#
# Usage: bash -c "$(curl -fsSL https://raw.githubusercontent.com/community-scripts/DevScripts/main/tools/pve/nanokvm-serial-console.sh)"
#        bash nanokvm-serial-console.sh plan|status|apply|undo [--yes]   (no prompts)
#
# Unattended via environment:
#   NANOKVM_SERIAL  the NanoKVM's USB serial number (Settings > USB on the
#                   NanoKVM), for a NanoKVM that is not plugged in yet

source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/core.func")
source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/lib/tools.func")
source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/error_handler.func")
source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/api/api.func") 2>/dev/null || true

load_functions
catch_errors
declare -f init_tool_telemetry &>/dev/null && init_tool_telemetry "nanokvm-serial-console" "pve"

# ==============================================================================
# CONFIGURATION
# ==============================================================================
APP="NanoKVM Serial Console"
APP_TYPE="tools"
VID=3346
PID=1009
RULE_FILE=/etc/udev/rules.d/90-nanokvm-serial-console.rules
BACKUP_DIR=/var/backups/nanokvm-serial-console
SERIAL="${NANOKVM_SERIAL:-}"

# ==============================================================================
# HELPERS
# ==============================================================================
usage() {
  cat <<EOF
${APP}: a login on the NanoKVM's USB serial port, for a Proxmox VE or PBS host.

  nanokvm-serial-console.sh                 menu
  nanokvm-serial-console.sh status          what the host has; changes nothing
  nanokvm-serial-console.sh plan            what apply would change; changes nothing
  nanokvm-serial-console.sh apply [--yes]   write the udev rule, start serial-getty@<port>
  nanokvm-serial-console.sh undo            revert the last apply

NANOKVM_SERIAL=<serial>  the NanoKVM's USB serial number (Settings > USB on the
                         NanoKVM), for a NanoKVM that is not plugged in now.
EOF
}

# What is on the USB bus and in the configuration now. Only reads.
look() {
  dev_serial="" dev_tty="" dev_path="" cdc_acm="" rule_serial="" foreign_rule="" getty_active=""
  local d t f
  for d in /sys/bus/usb/devices/*; do
    [[ -r $d/idVendor && -r $d/idProduct ]] || continue
    [[ $(<"$d/idVendor") == "$VID" && $(<"$d/idProduct") == "$PID" ]] || continue
    dev_path=$d
    [[ -r $d/serial ]] && dev_serial=$(<"$d/serial")
    for t in "$d"/*/tty/ttyACM*; do
      [[ -e $t ]] || continue
      dev_tty=${t##*/}
      break
    done
  done
  if [[ -n $SERIAL && -n $dev_serial && $SERIAL != "$dev_serial" ]]; then
    msg_warn "NANOKVM_SERIAL=$SERIAL differs from the connected NanoKVM ($dev_serial); using the connected one"
  fi
  if [[ -n $dev_serial ]]; then
    SERIAL=$dev_serial
  fi

  if [[ -d /sys/bus/usb/drivers/cdc_acm || -d /sys/module/cdc_acm ]]; then
    cdc_acm=loaded
  elif modinfo -n cdc_acm &>/dev/null; then
    cdc_acm=module
  fi

  if [[ -e $RULE_FILE ]]; then
    rule_serial=$(sed -n 's/.*ATTRS{serial}=="\([^"]*\)".*/\1/p' "$RULE_FILE" | head -n 1)
  fi
  # A login set up another way: someone else's udev rule that starts a getty
  # for this NanoKVM, or a getty running on its port that no rule started.
  # That setup is theirs; this script adds no second rule.
  for f in /etc/udev/rules.d/*.rules /lib/udev/rules.d/*.rules /usr/lib/udev/rules.d/*.rules; do
    [[ -r $f && $f != "$RULE_FILE" ]] || continue
    grep -q 'serial-getty@' "$f" || continue
    grep -qE "idVendor\"?\}?==\"$VID\"" "$f" || continue
    grep -qE "idProduct\"?\}?==\"$PID\"" "$f" || continue
    if [[ -z $SERIAL ]] || ! grep -q 'ATTRS{serial}==' "$f" || grep -q "ATTRS{serial}==\"$SERIAL\"" "$f"; then
      foreign_rule=$f
      break
    fi
  done
  if [[ -n $dev_tty ]] && systemctl is-active --quiet "serial-getty@$dev_tty.service"; then
    getty_active=yes
  fi
}

report() {
  look
  echo -e "${TAB}${BL}Host:${CL}     $PRODUCT, kernel $(uname -r)"
  if [[ -n $dev_tty ]]; then
    echo -e "${TAB}${BL}NanoKVM:${CL}  connected as /dev/$dev_tty (serial $dev_serial)"
  elif [[ -n $dev_path ]]; then
    echo -e "${TAB}${BL}NanoKVM:${CL}  connected at $dev_path but has no ttyACM: USB serial is not enabled on it, or cdc_acm is not loaded"
  elif [[ -n $SERIAL ]]; then
    echo -e "${TAB}${BL}NanoKVM:${CL}  not connected now; using serial $SERIAL"
  else
    echo -e "${TAB}${BL}NanoKVM:${CL}  not connected now and no serial number given: the rule cannot be bound to it"
  fi
  case $cdc_acm in
  loaded) echo -e "${TAB}${BL}Driver:${CL}   cdc_acm is loaded" ;;
  module) echo -e "${TAB}${BL}Driver:${CL}   cdc_acm module is available (loads when the device appears)" ;;
  *) echo -e "${TAB}${BL}Driver:${CL}   ${RD}no cdc_acm for $(uname -r): the port cannot appear${CL}" ;;
  esac
  if [[ -n $rule_serial ]]; then
    echo -e "${TAB}${BL}Login:${CL}    $RULE_FILE is present (serial $rule_serial)"
  elif [[ -n $foreign_rule ]]; then
    echo -e "${TAB}${BL}Login:${CL}    already set up by $foreign_rule (not by this script)"
  elif [[ -n $getty_active ]]; then
    echo -e "${TAB}${BL}Login:${CL}    serial-getty@$dev_tty.service is running, started by something else"
  else
    echo -e "${TAB}${BL}Login:${CL}    not set up"
  fi
  if [[ -n $dev_tty ]]; then
    echo -e "${TAB}${BL}Getty:${CL}    serial-getty@$dev_tty.service is $(systemctl is-active "serial-getty@$dev_tty.service" 2>/dev/null || true)"
  fi
  if command -v ModemManager &>/dev/null; then
    echo -e "${TAB}${BL}Note:${CL}     ModemManager is installed; the rule marks the port so it is not probed"
  fi
}

# What apply would do, or why it would not. Returns 1 when apply has nothing to do.
plan() {
  if [[ -z $cdc_acm ]]; then
    msg_error "Without cdc_acm the port never appears; the Proxmox kernel ships it, so check the running kernel."
    return 1
  fi
  if [[ -n $rule_serial && (-z $SERIAL || $rule_serial == "$SERIAL") ]]; then
    msg_ok "Nothing to do: already set up"
    return 1
  fi
  if [[ -n $foreign_rule ]]; then
    msg_ok "Nothing to do: the login is set up by $foreign_rule; this script adds no second rule (remove that one first if this script should own the setup)"
    return 1
  fi
  if [[ -z $SERIAL ]]; then
    msg_error "The NanoKVM is not connected and no serial number was given: apply needs it to bind the rule (Settings > USB on the NanoKVM shows it)."
    return 1
  fi
  echo -e "${TAB}${BL}Apply would:${CL}"
  if [[ -n $rule_serial ]]; then
    echo -e "${TAB3}replace $RULE_FILE (now for serial $rule_serial) with the rule for serial $SERIAL, keeping a backup"
  else
    echo -e "${TAB3}write $RULE_FILE: start serial-getty@<port> for NanoKVM serial $SERIAL, keep ModemManager off it"
  fi
  echo -e "${TAB3}udevadm control --reload, then trigger the add event for ${dev_tty:-the port when it appears}"
  echo -e "${TAB3}record the change in $BACKUP_DIR/<timestamp>/ for undo"
}

udev_rule() {
  cat <<EOF
# NanoKVM USB serial console, written by nanokvm-serial-console.sh 1.
# Starts a login (serial-getty@<port>) on the NanoKVM's CDC ACM port when it
# appears, and keeps ModemManager from probing it (the device-level and the
# port-level mark, for old and new ModemManager). Remove with
# "nanokvm-serial-console.sh undo", or delete this file and reload udev.
SUBSYSTEM=="usb", ATTR{idVendor}=="$VID", ATTR{idProduct}=="$PID", ATTR{serial}=="$SERIAL", ENV{ID_MM_DEVICE_IGNORE}="1"
ACTION=="add", SUBSYSTEM=="tty", KERNEL=="ttyACM[0-9]*", ATTRS{idVendor}=="$VID", ATTRS{idProduct}=="$PID", ATTRS{serial}=="$SERIAL", ENV{ID_MM_DEVICE_IGNORE}="1", ENV{ID_MM_PORT_IGNORE}="1", TAG+="systemd", ENV{SYSTEMD_WANTS}+="serial-getty@%k.service", SYMLINK+="nanokvm-console"
EOF
}

apply() {
  plan || return 0
  if [[ -z $ASSUME_YES ]] && ! prompt_confirm "Write the udev rule and start the login on the NanoKVM's port?" "n" 120; then
    msg_warn "Nothing changed"
    return 0
  fi
  local manifest
  manifest=$BACKUP_DIR/$(date +%Y%m%d-%H%M%S)
  while [[ -e $manifest ]]; do manifest=$manifest-1; done
  mkdir -p "$manifest"
  msg_info "Writing $RULE_FILE"
  if [[ -e $RULE_FILE ]]; then
    cp -p "$RULE_FILE" "$manifest/$(basename "$RULE_FILE").before"
    echo "replaced $RULE_FILE" >>"$manifest/manifest"
  else
    echo "created $RULE_FILE" >>"$manifest/manifest"
  fi
  udev_rule >"$RULE_FILE.nanokvm-new"
  chmod 0644 "$RULE_FILE.nanokvm-new"
  mv "$RULE_FILE.nanokvm-new" "$RULE_FILE"
  printf 'serial %s\nversion 1\n' "$SERIAL" >>"$manifest/manifest"
  msg_ok "Wrote $RULE_FILE (recorded in $manifest)"

  msg_info "Reloading udev"
  udevadm control --reload
  msg_ok "Reloaded udev"
  if [[ -z $dev_tty ]]; then
    msg_ok "The login starts when the NanoKVM's port appears"
    return 0
  fi
  msg_info "Starting the login on /dev/$dev_tty"
  # match flags, not a device path: old udevadm has no positional argument
  udevadm trigger --subsystem-match=tty "--sysname-match=$dev_tty" --action=add
  sleep 1
  # A repeated add event for a device that is already there does not always
  # start the wanted unit (seen on systemd 247 after an undo); the rule covers
  # the next plug and boot, so start it now.
  systemctl is-active --quiet "serial-getty@$dev_tty.service" || systemctl start "serial-getty@$dev_tty.service"
  sleep 1
  if systemctl is-active --quiet "serial-getty@$dev_tty.service"; then
    msg_ok "serial-getty@$dev_tty.service is running: open the USB serial console on the NanoKVM and press Enter"
  else
    msg_error "serial-getty@$dev_tty.service is not active; check: systemctl status serial-getty@$dev_tty.service"
  fi
}

undo() {
  local last="" d kind path
  for d in "$BACKUP_DIR"/*/; do
    [[ -r $d/manifest ]] && last=${d%/}
  done
  if [[ -z $last ]]; then
    msg_ok "Nothing to undo: no manifest in $BACKUP_DIR"
    return 0
  fi
  msg_info "Undoing $(basename "$last")"
  while read -r kind path; do
    case $kind in
    created) rm -f "$path" ;;
    replaced) cp -p "$last/$(basename "$path").before" "$path" ;;
    esac
  done <"$last/manifest"
  mv "$last/manifest" "$last/manifest.undone"
  udevadm control --reload
  if [[ -n $dev_tty ]]; then
    systemctl stop "serial-getty@$dev_tty.service"
  fi
  msg_ok "Undone $(basename "$last"); the backups stay in $last"
}

# ==============================================================================
# MAIN
# ==============================================================================
ACTION=""
ASSUME_YES=""
while [[ $# -gt 0 ]]; do
  case $1 in
  plan | status | apply | undo) ACTION=$1 ;;
  --yes | -y) ASSUME_YES=yes ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    msg_error "Usage: nanokvm-serial-console.sh [plan|status|apply|undo] [--yes]"
    exit 1
    ;;
  esac
  shift
done
if [[ -z $ACTION ]] && is_unattended; then
  ACTION=plan
fi
[[ -n $ACTION ]] || header_info "$APP"
root_check

if on_pve_host; then
  PVE_VER=$(_pve_version)
  PRODUCT="Proxmox VE $PVE_VER"
  # pve_check also wants /etc/pve mounted; a console for a host in trouble
  # must not depend on that, so only the version policy is kept.
  [[ $PVE_VER =~ ^(8|9)\. ]] || {
    msg_error "Proxmox VE $PVE_VER is not supported (8.x and 9.x are)."
    exit 1
  }
elif command -v proxmox-backup-manager &>/dev/null; then
  PRODUCT="Proxmox Backup Server $(proxmox-backup-manager versions 2>/dev/null | awk 'NR==1 {print $2}')"
  case "$(awk -F= '/^VERSION_CODENAME=/ {print $2}' /etc/os-release)" in
  bookworm | trixie) ;;
  *)
    msg_error "Unsupported Debian release for Proxmox Backup Server: $(awk -F= '/^PRETTY_NAME=/ {print $2}' /etc/os-release)"
    exit 1
    ;;
  esac
else
  msg_error "This script must be run on a Proxmox VE or Proxmox Backup Server host."
  exit 232
fi
if systemd-detect-virt -cq 2>/dev/null; then
  msg_error "This is a container: udev and the USB device belong to the host; run this there."
  exit 1
fi

if [[ -n $ACTION ]]; then
  report
  echo
  case $ACTION in
  status) ;;
  plan) plan || true ;;
  apply) apply ;;
  undo) undo ;;
  esac
  exit 0
fi

echo
report
while true; do
  echo
  CHOICE=$(prompt_select "What now? plan: what Apply would change (changes nothing) | apply: set the login up | undo: remove what Apply added | serial: enter the serial number of a NanoKVM that is not plugged in | quit" 1 300 plan apply undo serial quit)
  echo
  case $CHOICE in
  plan)
    look
    plan || true
    ;;
  apply)
    look
    apply
    ;;
  undo)
    look
    undo
    ;;
  serial)
    SERIAL=$(prompt_input "NanoKVM USB serial number (Settings > USB on the NanoKVM):" "$SERIAL" 300)
    ;;
  *) exit 0 ;;
  esac
done
