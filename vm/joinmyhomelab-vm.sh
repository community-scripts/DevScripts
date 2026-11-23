#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: BASH3R
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://joinmyhomelab.com

COMMUNITY_SCRIPTS_URL="${COMMUNITY_SCRIPTS_URL:-https://raw.githubusercontent.com/community-scripts/DevScripts/main}"
source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/pve/vm-core.func")
load_functions

GEN_MAC=02:$(openssl rand -hex 5 | awk '{print toupper($0)}' | sed 's/\(..\)/\1:/g; s/.$//')
RANDOM_UUID="$(cat /proc/sys/kernel/random/uuid)"
METHOD=""
APP="Join My Homelab"
APP_TYPE="vm"
NSAPP="joinmyhomelab-vm"
var_os="talos"
var_version="n.d."

THIN="discard=on,ssd=1,"

header_info
echo -e "\n Loading..."
set -Eeo pipefail
shopt -s inherit_errexit
trap 'error_handler $LINENO "$BASH_COMMAND"' ERR
trap cleanup EXIT
trap 'post_update_to_api "failed" "130"' SIGINT
trap 'post_update_to_api "failed" "143"' SIGTERM
trap 'post_update_to_api "failed" "129"; exit 129' SIGHUP

vm_require_arch amd64

TEMP_DIR=$(mktemp -d)
pushd "$TEMP_DIR" >/dev/null

function default_settings() {
  vm_apply_machine_type "q35"
  VMID=$(get_valid_nextid)
  DISK_SIZE="50G"
  DISK_CACHE=""
  HN="joinmyhomelab-node"
  CPU_TYPE=" -cpu host"
  CORE_COUNT="4"
  RAM_SIZE="8192"
  BRG="vmbr0"
  MAC="$GEN_MAC"
  VLAN=""
  MTU=""
  START_VM="yes"
  METHOD="default"
  vm_echo_default_settings
}

function advanced_settings() {
  METHOD="advanced"
  vm_prompt_vmid "${VMID:-$(get_valid_nextid)}"
  vm_prompt_machine_type "q35"
  vm_prompt_disk_size "50G"
  vm_prompt_disk_cache "none"
  vm_prompt_hostname "joinmyhomelab-node"
  vm_prompt_cpu_model "host"
  vm_prompt_cpu_cores "4"
  vm_prompt_ram "8192"
  vm_prompt_bridge "vmbr0"
  vm_prompt_mac "$GEN_MAC"
  vm_prompt_vlan
  vm_prompt_mtu
  vm_prompt_start_vm "yes"

  if vm_confirm_advanced_settings "Ready to create a Join My Homelab node?"; then
    echo -e "${CREATING}${BOLD}${DGN}Creating a Join My Homelab node using the above advanced settings${CL}"
  else
    header_info
    echo -e "${ADVANCED}${BOLD}${RD}Using Advanced Settings${CL}"
    advanced_settings
  fi
}

vm_preflight
vm_start_script "Use Default Settings?\n\nDefaults:\n• 4 CPU Cores\n• 8 GB RAM\n• 50 GB Disk\n• Nested virtualisation required" 14 58
post_to_api_vm

var_iso_url="${VM_ISO_URL:-}"

if [[ -z "$var_iso_url" && "${VM_UNATTENDED:-0}" != "1" ]] && command -v ssh >/dev/null 2>&1; then
  msg_info "Asking joinmyhomelab.com for this machine's image"
  var_iso_url="$(ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=8 \
    -T dashboard@joinmyhomelab.com -- --iso-url 2>/dev/null | tr -d '\r' | tail -n 1)" || true
  [[ "$var_iso_url" == https://* ]] || var_iso_url=""
fi

IMAGE_MISSING=""
if [[ -z "$var_iso_url" ]]; then
  if [[ "${VM_UNATTENDED:-0}" == "1" ]]; then
    IMAGE_MISSING="yes"
    msg_warn "VM_ISO_URL is not set: creating the VM without the Join My Homelab image"
  else
    while true; do
      if vm_dialog inputbox "PERSONAL IMAGE URL" \
        "Paste the image URL from your Join My Homelab dashboard.\n\nGet it with:\n  ssh dashboard@joinmyhomelab.com\nthen \"Download your ISO\".\n\nThe first connection creates your account." \
        15 70 "" --cancel-button Exit-Script; then
        var_iso_url="$VM_DIALOG_RESULT"
        [[ "$var_iso_url" =~ ^https?:// ]] && break
        vm_dialog msgbox "INVALID URL" "The image URL must start with http:// or https://" 8 60
      else
        exit_script
      fi
    done
  fi
fi

nested="unknown"
[[ -r /sys/module/kvm_intel/parameters/nested ]] && nested="$(cat /sys/module/kvm_intel/parameters/nested)"
[[ -r /sys/module/kvm_amd/parameters/nested ]] && nested="$(cat /sys/module/kvm_amd/parameters/nested)"
case "$nested" in
Y | 1 | y) ;;
*)
  msg_warn "Nested virtualisation is off: the node joins, but VMs on it will not start."
  echo -e "${TAB}Enable it: echo 'options kvm_intel nested=1' > /etc/modprobe.d/kvm-nested.conf (kvm_amd on AMD), then reboot."
  ;;
esac

vm_select_storage "$HN"

if [[ "$IMAGE_MISSING" != "yes" ]]; then
  ISO_NAME="$(basename "${var_iso_url%%\?*}")"
  [[ "$ISO_NAME" == *.iso ]] || ISO_NAME="joinmyhomelab-node.iso"
  vm_select_iso_storage "$ISO_NAME" "$HN"
  CACHE_FILE="$ISO_PATH"
  [[ -s "$CACHE_FILE" ]] || msg_info "Downloading the Join My Homelab image (about 350 MB)"
  vm_fetch_image "$var_iso_url" "$CACHE_FILE" --cache --min-bytes $((100 * 1024 * 1024)) || exit 115
fi

msg_info "Creating a Join My Homelab node"
vm_claim_vmid
if [[ "$IMAGE_MISSING" == "yes" ]]; then
  qm create "$VMID"${MACHINE}${CPU_TYPE} -cores "$CORE_COUNT" -memory "$RAM_SIZE" -name "$HN" \
    -tags community-script,joinmyhomelab -net0 "virtio,bridge=$BRG,macaddr=$MAC$VLAN$MTU" -onboot 1 \
    -ostype l26 -scsihw virtio-scsi-pci -serial0 socket -vga std \
    -scsi0 "${STORAGE}:${DISK_SIZE%G},${DISK_CACHE:-}${THIN%,}" \
    -boot order='scsi0' >/dev/null
else
  qm create "$VMID"${MACHINE}${CPU_TYPE} -cores "$CORE_COUNT" -memory "$RAM_SIZE" -name "$HN" \
    -tags community-script,joinmyhomelab -net0 "virtio,bridge=$BRG,macaddr=$MAC$VLAN$MTU" -onboot 1 \
    -ostype l26 -scsihw virtio-scsi-pci -serial0 socket -vga std \
    -scsi0 "${STORAGE}:${DISK_SIZE%G},${DISK_CACHE:-}${THIN%,}" \
    -ide2 "$ISO_VOLUME,media=cdrom" -boot order='scsi0;ide2' >/dev/null
fi
vm_mark_created

set_description
msg_ok "Created a Join My Homelab node ${CL}${BL}(${HN})"

vm_start_vm "Join My Homelab node"
vm_print_summary "Image=${var_iso_url:-none}" "Dashboard=ssh dashboard@joinmyhomelab.com"
vm_next_steps \
  "Open the console in Proxmox (noVNC) to watch the node install." \
  "It installs itself, reboots, and joins the cluster." \
  "The dashboard shows the node green when it is ready: ssh dashboard@joinmyhomelab.com"
vm_finish "VM created. The node installs and joins the cluster on first boot."
