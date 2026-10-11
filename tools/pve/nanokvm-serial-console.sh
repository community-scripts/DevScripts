#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Gleb Pesin (dormancygrace)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/dormancygrace/NanoKVM-OS

# NanoKVM USB serial console for a Proxmox VE or Proxmox Backup Server host.
#
# A NanoKVM plugged into the host offers a USB serial port (CDC ACM, USB
# 3346:1009, /dev/ttyACMn). This sets up a login on it, so the host stays
# reachable from the NanoKVM's browser terminal when its network is gone:
# one udev rule bound to the NanoKVM's serial number starts
# serial-getty@<port> whenever the port appears. The change is recorded with
# backups under /var/backups/nanokvm-serial-console and reverted by "undo".
#
# Usage: bash -c "$(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/tools/pve/nanokvm-serial-console.sh)"
#        bash nanokvm-serial-console.sh plan|status|apply|undo [--serial SERIAL]   (no dialogs)

function header_info {
  clear
  cat <<"EOF"
    _   __                __ ___    ____  ___              _       __
   / | / /___ _____  ____/ //_/ |  / /  |/  /  _______  __(_)___ _/ /
  /  |/ / __ `/ __ \/ __  / ,<  | | / / /|_/ /  / ___/ _ \/ ___/ / __ `/ /
 / /|  / /_/ / / / / /_/ / /| | | |/ / /  / /  (__  )  __/ /  / / /_/ / /
/_/ |_/\__,_/_/ /_/\____/_/ |_| |___/_/  /_/  /____/\___/_/  /_/\__,_/_/

                     USB serial console on this host
EOF
}

YW="\033[33m"
GN="\033[1;92m"
RD="\033[01;31m"
CL="\033[m"
BFR="\\r\\033[K"
HOLD="-"
CM="${GN}✓${CL}"
CROSS="${RD}✗${CL}"

msg_info() { echo -ne " ${HOLD} ${YW}$1..."; }
msg_ok() { echo -e "${BFR} ${CM} ${GN}$1${CL}"; }
msg_error() { echo -e "${BFR} ${CROSS} ${RD}$1${CL}"; }
msg_warn() { echo -e " ${YW}$1${CL}"; }

# Telemetry
# shellcheck disable=SC1090
source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/api/api.func" 2>/dev/null) 2>/dev/null || true
declare -f init_tool_telemetry &>/dev/null && init_tool_telemetry "nanokvm-serial-console" "pve"

VID=3346
PID=1009
RULE_FILE=/etc/udev/rules.d/90-nanokvm-serial-console.rules
BACKUP_DIR=/var/backups/nanokvm-serial-console

# Arguments: no dialogs.
SERIAL=
ACTION=
while [[ $# -gt 0 ]]; do
  case $1 in
  plan | status | apply | undo) ACTION=$1 ;;
  --serial)
    SERIAL=${2:-}
    shift
    ;;
  --serial=*) SERIAL=${1#--serial=} ;;
  -h | --help)
    cat <<EOF
NanoKVM USB serial console for a Proxmox VE or Proxmox Backup Server host.

  nanokvm-serial-console.sh                     menu (whiptail)
  nanokvm-serial-console.sh status              what the host has; changes nothing
  nanokvm-serial-console.sh plan                what apply would change; changes nothing
  nanokvm-serial-console.sh apply [--serial S]  write the udev rule, start serial-getty@<port>
  nanokvm-serial-console.sh undo                revert the last apply

--serial SERIAL  the NanoKVM's USB serial number (Settings > USB on the NanoKVM),
                 for a NanoKVM that is not plugged in now.
EOF
    exit 0
    ;;
  *)
    msg_error "Usage: $0 [plan|status|apply|undo] [--serial SERIAL]"
    exit 1
    ;;
  esac
  shift
done
if [[ $EUID -ne 0 ]]; then
  msg_error "Run this as root on the Proxmox host."
  exit 1
fi

if command -v pveversion >/dev/null 2>&1; then
  PRODUCT="Proxmox VE $(pveversion | sed -n 's|^pve-manager/\([0-9.]*\).*|\1|p')"
elif command -v proxmox-backup-manager >/dev/null 2>&1; then
  PRODUCT="Proxmox Backup Server $(proxmox-backup-manager versions 2>/dev/null | awk 'NR==1 {print $2}')"
else
  msg_error "No Proxmox VE or Proxmox Backup Server detected."
  exit 1
fi
case "$(awk -F= '/^VERSION_CODENAME=/ {print $2}' /etc/os-release)" in
bookworm | trixie) ;;
bullseye) msg_warn "Debian 11 (Proxmox VE 7 / PBS 2) is past its support; the console setup still works on it." ;;
*)
  msg_error "Unsupported Debian release: $(awk -F= '/^PRETTY_NAME=/ {print $2}' /etc/os-release)"
  exit 1
  ;;
esac
if systemd-detect-virt -cq 2>/dev/null; then
  msg_error "This is a container: udev and the USB device belong to the host; run this there."
  exit 1
fi

# What is on the USB bus and in the configuration now. Everything below only
# reads; apply and undo are the only writers.
look() {
  dev_serial=
  dev_tty=
  dev_path=
  for d in /sys/bus/usb/devices/*; do
    [[ -r $d/idVendor ]] || continue
    if [[ $(<"$d/idVendor") == "$VID" && $(<"$d/idProduct") == "$PID" ]]; then
      dev_path=$d
      dev_serial=$(<"$d/serial")
      for t in "$d"/*/tty/ttyACM*; do
        [[ -e $t ]] && dev_tty=${t##*/} && break
      done
    fi
  done
  if [[ -n $SERIAL && -n $dev_serial && $SERIAL != "$dev_serial" ]]; then
    msg_warn "--serial $SERIAL differs from the connected NanoKVM ($dev_serial); using the connected one"
  fi
  [[ -n $dev_serial ]] && SERIAL=$dev_serial

  cdc_acm=
  if [[ -d /sys/bus/usb/drivers/cdc_acm || -d /sys/module/cdc_acm ]]; then
    cdc_acm=loaded
  elif modinfo -n cdc_acm >/dev/null 2>&1; then
    cdc_acm=module
  fi

  rule_serial=
  [[ -e $RULE_FILE ]] && rule_serial=$(sed -n 's/.*ATTRS{serial}=="\([^"]*\)".*/\1/p' "$RULE_FILE" | head -n 1)
  # A login set up another way: someone else's udev rule that starts a getty
  # for this NanoKVM, or a getty running on its port that no rule started.
  # That setup is theirs; this script adds no second rule.
  foreign_rule=
  for f in /etc/udev/rules.d/*.rules /lib/udev/rules.d/*.rules /usr/lib/udev/rules.d/*.rules; do
    [[ -r $f && $f != "$RULE_FILE" ]] || continue
    if grep -q 'serial-getty@' "$f" && grep -qE "idVendor\"?\}?==\"$VID\"" "$f" && grep -qE "idProduct\"?\}?==\"$PID\"" "$f"; then
      if [[ -z $SERIAL ]] || ! grep -q 'ATTRS{serial}==' "$f" || grep -q "ATTRS{serial}==\"$SERIAL\"" "$f"; then
        foreign_rule=$f
        break
      fi
    fi
  done
  getty_active=
  [[ -n $dev_tty ]] && systemctl is-active --quiet "serial-getty@$dev_tty.service" && getty_active=yes
}

report() {
  look
  echo -e " ${YW}Host:${CL}     $PRODUCT, $(uname -r)"
  if [[ -n $dev_tty ]]; then
    echo -e " ${YW}NanoKVM:${CL}  connected as /dev/$dev_tty (serial $dev_serial)"
  elif [[ -n $dev_path ]]; then
    echo -e " ${YW}NanoKVM:${CL}  connected at $dev_path but has no ttyACM: USB serial is not enabled on it, or cdc_acm is not loaded"
  elif [[ -n $SERIAL ]]; then
    echo -e " ${YW}NanoKVM:${CL}  not connected now; using serial $SERIAL"
  else
    echo -e " ${YW}NanoKVM:${CL}  not connected now and no serial number given: the rule cannot be bound to it"
  fi
  case $cdc_acm in
  loaded) echo -e " ${YW}Driver:${CL}   cdc_acm is loaded" ;;
  module) echo -e " ${YW}Driver:${CL}   cdc_acm module is available (loads when the device appears)" ;;
  *) echo -e " ${YW}Driver:${CL}   ${RD}no cdc_acm for $(uname -r): the port cannot appear${CL}" ;;
  esac
  if [[ -n $rule_serial ]]; then
    echo -e " ${YW}Login:${CL}    $RULE_FILE is present (serial $rule_serial)"
  elif [[ -n $foreign_rule ]]; then
    echo -e " ${YW}Login:${CL}    already set up by $foreign_rule (not by this script)"
  elif [[ -n $getty_active ]]; then
    echo -e " ${YW}Login:${CL}    serial-getty@$dev_tty.service is running, started by something else"
  else
    echo -e " ${YW}Login:${CL}    not set up"
  fi
  [[ -n $dev_tty ]] && echo -e " ${YW}Getty:${CL}    serial-getty@$dev_tty.service is $(systemctl is-active "serial-getty@$dev_tty.service" 2>/dev/null)"
  if command -v ModemManager >/dev/null 2>&1; then
    echo -e " ${YW}Note:${CL}     ModemManager is installed; the rule marks the port so it is not probed"
  fi
}

# plan: what apply would do, or why it would not. Returns 1 when apply has
# nothing to do.
plan() {
  if [[ -z $cdc_acm ]]; then
    msg_error "Without cdc_acm the port never appears; the Proxmox kernel ships it, so check the running kernel."
    return 1
  fi
  if [[ -n $rule_serial && ( -z $SERIAL || $rule_serial == "$SERIAL" ) ]]; then
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
  echo -e " ${YW}Apply would:${CL}"
  if [[ -n $rule_serial ]]; then
    echo "   replace $RULE_FILE (now for serial $rule_serial) with the rule for serial $SERIAL, keeping a backup"
  else
    echo "   write $RULE_FILE: start serial-getty@<port> for NanoKVM serial $SERIAL, keep ModemManager off it"
  fi
  echo "   udevadm control --reload, then trigger the add event for ${dev_tty:-the port when it appears}"
  echo "   record the change in $BACKUP_DIR/<timestamp>/ for undo"
  return 0
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
  # systemd 247 (Debian 11) does not start the wanted unit on a repeated add
  # event for a device that is already there; the rule covers the next plug
  # and boot, so start it now.
  systemctl is-active --quiet "serial-getty@$dev_tty.service" || systemctl start "serial-getty@$dev_tty.service"
  sleep 1
  if systemctl is-active --quiet "serial-getty@$dev_tty.service"; then
    msg_ok "serial-getty@$dev_tty.service is running: open the USB serial console on the NanoKVM and press Enter"
  else
    msg_error "serial-getty@$dev_tty.service is not active; check: systemctl status serial-getty@$dev_tty.service"
  fi
}

undo() {
  local last=
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
  [[ -n $dev_tty ]] && systemctl stop "serial-getty@$dev_tty.service"
  msg_ok "Undone $(basename "$last"); the backups stay in $last"
}

if [[ -n $ACTION ]]; then
  report
  echo
  case $ACTION in
  status) exit 0 ;;
  plan) plan ;;
  apply) apply ;;
  undo) undo ;;
  esac
  exit 0
fi

header_info
echo
report
echo
while true; do
  CHOICE=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "NanoKVM USB serial console" --menu \
    "The report above says what this host has. What now?" 16 72 5 \
    "plan" "Show what Apply would change (changes nothing)" \
    "apply" "Set the login up (udev rule, serial-getty@<port>)" \
    "undo" "Remove what Apply added" \
    "serial" "Enter the NanoKVM's USB serial number (not plugged in yet)" \
    "quit" "Leave" 3>&1 1>&2 2>&3) || exit 0
  case $CHOICE in
  plan)
    echo
    look
    plan || true
    ;;
  apply)
    if whiptail --backtitle "Proxmox VE Helper Scripts" --title "Apply" --yesno \
      "Write the udev rule and start the login on the NanoKVM's port?\n\nBackups and a manifest go to $BACKUP_DIR; Undo reverts it." 12 72; then
      echo
      look
      apply
    fi
    ;;
  undo)
    echo
    look
    undo
    ;;
  serial)
    SERIAL=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "NanoKVM serial number" --inputbox \
      "The USB serial number shown on the NanoKVM's USB settings page (Settings > USB), for a NanoKVM that is not plugged in now." 10 72 "${SERIAL:-}" 3>&1 1>&2 2>&3) || true
    ;;
  quit) exit 0 ;;
  esac
  echo
  read -r -p "Press Enter to return to the menu " _ || true
done
