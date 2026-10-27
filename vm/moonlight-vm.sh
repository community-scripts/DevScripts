#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Tomblarom
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://moonlight-stream.org

COMMUNITY_SCRIPTS_URL="${COMMUNITY_SCRIPTS_URL:-https://raw.githubusercontent.com/community-scripts/DevScripts/main}"
source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/pve/vm-core.func")
load_functions

APP="Moonlight"
APP_TYPE="vm"
NSAPP="moonlight-vm"
var_os="debian"
var_version="13"
GEN_MAC=02:$(openssl rand -hex 5 | awk '{print toupper($0)}' | sed 's/\(..\)/\1:/g; s/.$//')
RANDOM_UUID="$(cat /proc/sys/kernel/random/uuid)"
METHOD=""
THIN="discard=on,ssd=1,"
USE_CLOUD_INIT="no"

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

vm_preflight
vm_require_tools virt-customize jq lspci

function select_client_options() {
  if [[ "${VM_UNATTENDED:-0}" == 1 ]]; then
    VM_CLIENT_AUTOSTART="${VM_CLIENT_AUTOSTART:-yes}"
    VM_DESKTOP_AUTOLOGIN="${VM_DESKTOP_AUTOLOGIN:-no}"
  else
    if [[ -z "${VM_CLIENT_AUTOSTART:-}" ]]; then
      vm_dialog radiolist "MOONLIGHT AUTOSTART" "Start Moonlight after graphical login?" 12 68 2 \
        yes "Start Moonlight" ON no "Open the desktop" OFF || exit_script
      VM_CLIENT_AUTOSTART="$VM_DIALOG_RESULT"
    fi
    if [[ -z "${VM_DESKTOP_AUTOLOGIN:-}" ]]; then
      vm_dialog radiolist "DESKTOP AUTOLOGIN" "Log ${CLOUDINIT_USER} into the desktop without asking for a password?" 12 68 2 \
        no "Ask for credentials" ON yes "Log in automatically" OFF || exit_script
      VM_DESKTOP_AUTOLOGIN="$VM_DIALOG_RESULT"
    fi
  fi
  if [[ ! "$VM_CLIENT_AUTOSTART" =~ ^(yes|no)$ || ! "$VM_DESKTOP_AUTOLOGIN" =~ ^(yes|no)$ ]]; then
    msg_error "VM_CLIENT_AUTOSTART and VM_DESKTOP_AUTOLOGIN must be yes or no."
    exit 1
  fi
  echo -e "${INFO}${BOLD}${DGN}Moonlight autostart: ${BGN}${VM_CLIENT_AUTOSTART}${CL}"
  echo -e "${INFO}${BOLD}${DGN}Desktop autologin: ${BGN}${VM_DESKTOP_AUTOLOGIN}${CL}"
}

function validate_gpu_passthrough() {
  local address="${VM_GPU_PCI:-}" device function member class config value slot driver
  GPU_SLOT=""
  [[ -z "$address" || "$address" == none ]] && return 0
  [[ "$address" =~ ^([[:xdigit:]]{4}:)?[[:xdigit:]]{2}:[[:xdigit:]]{2}\.[0-7]$ ]] || {
    msg_error "VM_GPU_PCI must name one GPU function, for example 0000:01:00.0."
    return 1
  }
  [[ "$address" == ????:??:??.? ]] || address="0000:$address"
  address="${address,,}"
  device="/sys/bus/pci/devices/$address"
  [[ -r "$device/class" && "$(<"$device/class")" == 0x03* ]] || {
    msg_error "The selected PCI function is not a display controller: $address"
    return 1
  }
  slot="${address%.*}"
  for function in /sys/bus/pci/devices/"$slot".*; do
    [[ -e "$function/iommu_group" ]] || {
      msg_error "No IOMMU group for ${function##*/}. Enable VT-d/AMD-Vi in firmware and prepare PCI passthrough first: https://pve.proxmox.com/wiki/PCI_Passthrough"
      return 1
    }
    [[ ! -r "$function/boot_vga" || "$(<"$function/boot_vga")" != 1 ]] || {
      msg_error "${function##*/} is the boot display. Configure this GPU manually to protect the host console."
      return 1
    }
    driver="$(readlink "$function/driver" 2>/dev/null || true)"
    [[ "${driver##*/}" == vfio-pci ]] || {
      msg_error "${function##*/} must already use vfio-pci. Prepare this specific device using the Proxmox PCI passthrough guide, or choose no GPU. Host drivers and boot settings are not changed here."
      return 1
    }
    for member in "$function"/iommu_group/devices/*; do
      [[ -r "$member/class" ]] || return 1
      class="$(<"$member/class")"
      [[ "${member##*/}" == "$slot".* || "$class" == 0x0604* ]] || {
        msg_error "IOMMU group also contains ${member##*/}. Select an isolated GPU; ACS overrides are not configured."
        return 1
      }
    done
  done
  for config in /etc/pve/qemu-server/*.conf; do
    [[ -f "$config" ]] || continue
    while IFS= read -r value; do
      [[ "$value" != *mapping=* ]] || {
        msg_error "A local VM uses a PCI resource mapping. Check mapped-device ownership and attach the GPU manually in Proxmox."
        return 1
      }
      value="${value,,}"
      # hostpci accepts domain-less addresses, individual functions and semicolon lists.
      value="${value//0000:/}"
      value="${value//host=/}"
      if [[ "$value" =~ (^|[\;[:space:]])${slot#0000:}(\.[0-7])?([\;,[:space:]]|$) ]]; then
        msg_error "The selected GPU is already assigned in ${config##*/}."
        return 1
      fi
    done < <(sed -n 's/^hostpci[0-9][0-9]*: *//p' "$config")
  done
  GPU_SLOT="$slot"
}

function validate_usb_passthrough() {
  local port interface class config value vendor product
  USB_PORTS=()
  [[ -z "${VM_USB_PORTS:-}" || "$VM_USB_PORTS" == none ]] && return 0
  [[ "$VM_USB_PORTS" != ,* && "$VM_USB_PORTS" != *, && "$VM_USB_PORTS" != *,,* ]] || return 1
  IFS=, read -r -a USB_PORTS <<<"$VM_USB_PORTS"
  (( ${#USB_PORTS[@]} <= 14 )) || { msg_error "Select at most 14 USB ports."; return 1; }
  local -A seen=()
  for port in "${USB_PORTS[@]}"; do
    [[ "$port" =~ ^[1-9][0-9]*-[1-9][0-9]*(\.[1-9][0-9]*)*$ && -r "/sys/bus/usb/devices/$port/idVendor" ]] || {
      msg_error "USB port is invalid or disconnected: $port"
      return 1
    }
    [[ -z "${seen[$port]:-}" ]] || { msg_error "USB port selected twice: $port"; return 1; }
    seen[$port]=1
    for interface in /sys/bus/usb/devices/"$port"/bDeviceClass /sys/bus/usb/devices/"$port":*/bInterfaceClass; do
      [[ -r "$interface" ]] || continue
      class="$(<"$interface")"
      case "${class,,}" in
      08 | 09 | 02 | 0a) msg_error "USB storage, hubs and network devices are not supported by this picker: $port"; return 1 ;;
      esac
    done
    vendor="$(<"/sys/bus/usb/devices/$port/idVendor")"
    product="$(<"/sys/bus/usb/devices/$port/idProduct")"
    for config in /etc/pve/qemu-server/*.conf; do
      [[ -f "$config" ]] || continue
      while IFS= read -r value; do
        if [[ "$value" == *mapping=* || "$value" == *"host=$port,"* || "$value" == *"host=$port" || "$value" == *"host=$vendor:$product"* ]]; then
          msg_error "USB port or matching USB ID may already be assigned in ${config##*/}. Check ownership manually."
          return 1
        fi
      done < <(sed -n 's/^usb[0-9][0-9]*: *//p' "$config")
    done
  done
}

function select_passthrough() {
  local device address label port summary="" vendor product
  local -a choices=(none "Configure GPU later (no hardware acceleration promised)" ON)
  GPU_SLOT=""
  USB_PORTS=()
  if [[ -z "${VM_GPU_PCI:-}" && "${VM_UNATTENDED:-0}" != 1 ]]; then
    for device in /sys/bus/pci/devices/*; do
      [[ -r "$device/class" && "$(<"$device/class")" == 0x03* ]] || continue
      address="${device##*/}"
      label="$(lspci -D -s "$address" -nn)"
      choices+=("$address" "$label" OFF)
    done
    vm_dialog radiolist "GPU PASSTHROUGH" "Select one prepared GPU. Every function in its PCI slot will be dedicated to this VM. No GPU is selected automatically." 18 90 8 "${choices[@]}" || exit_script
    VM_GPU_PCI="$VM_DIALOG_RESULT"
  fi
  validate_gpu_passthrough || return 1
  if [[ -n "$GPU_SLOT" && -r "/sys/bus/pci/devices/$GPU_SLOT.0/vendor" ]] &&
    [[ "$(<"/sys/bus/pci/devices/$GPU_SLOT.0/vendor")" == 0x10de ]]; then
    msg_warn "Install a compatible NVIDIA driver inside the guest before testing hardware encoding/decoding; this installer stages AMD/Intel Mesa drivers."
  fi
  if [[ "$NSAPP" == moonlight-vm ]]; then
    if [[ -z "${VM_USB_PORTS:-}" && "${VM_UNATTENDED:-0}" != 1 ]]; then
      summary="USB devices by physical port (none are preselected):"
      for device in /sys/bus/usb/devices/*/idVendor; do
        port="${device%/idVendor}"
        port="${port##*/}"
        [[ "$port" =~ ^[1-9][0-9]*-[1-9][0-9]*(\.[1-9][0-9]*)*$ ]] || continue
        vendor="$(<"$device")"
        product="$(<"${device%/idVendor}/idProduct")"
        label=""
        [[ ! -r "${device%/idVendor}/product" ]] || label="$(<"${device%/idVendor}/product")"
        summary+="\n$port  $vendor:$product  $label"
      done
      vm_dialog inputbox "USB PASSTHROUGH" "$summary\n\nEnter comma-separated ports, for example 1-2,1-3.4, or none. They become exclusive to the VM; reconnecting another device to the same port also passes it through." 20 90 none || exit_script
      VM_USB_PORTS="$VM_DIALOG_RESULT"
    fi
    validate_usb_passthrough || return 1
  fi
  if [[ -n "$GPU_SLOT" || ${#USB_PORTS[@]} -gt 0 ]]; then
    if [[ "${VM_UNATTENDED:-0}" == 1 ]]; then
      [[ "${VM_PASSTHROUGH_CONFIRM:-no}" == yes ]] || {
        msg_error "Unattended device assignment requires VM_PASSTHROUGH_CONFIRM=yes."
        return 1
      }
    else
      summary="Dedicated GPU slot: ${GPU_SLOT:-none}\nUSB ports: ${VM_USB_PORTS:-none}\n"
      if [[ -n "$GPU_SLOT" ]]; then
        for device in /sys/bus/pci/devices/"$GPU_SLOT".*; do
          summary+="\n$(lspci -D -s "${device##*/}" -nn)"
        done
      fi
      vm_dialog yesno "CONFIRM DEVICE ASSIGNMENT" "$summary\n\nThese devices become exclusive to this VM. GPU output requires a connected monitor/dummy and is unavailable in noVNC. SSH and serial console remain available. Apply these assignments to the new VM?" 21 90 || exit_script
    fi
  fi
}

function attach_passthrough() {
  local index
  # Recheck after downloading/provisioning, before changing device ownership.
  validate_gpu_passthrough || return 1
  if [[ "$NSAPP" == moonlight-vm ]]; then
    validate_usb_passthrough || return 1
  fi
  if [[ -n "$GPU_SLOT" ]]; then
    qm set "$VMID" --hostpci0 "$GPU_SLOT,pcie=1" --vga none >/dev/null
  fi
  for index in "${!USB_PORTS[@]}"; do
    qm set "$VMID" "--usb$index" "host=${USB_PORTS[$index]},usb3=1" >/dev/null
  done
}

function default_settings() {
  VMID=$(get_valid_nextid)
  vm_apply_machine_type "q35"
  DISK_SIZE="16G"
  DISK_CACHE=""
  HN="moonlight"
  CPU_TYPE=" -cpu host"
  CORE_COUNT="2"
  RAM_SIZE="2048"
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
  vm_apply_machine_type "q35"
  vm_prompt_disk_size "16G" "Set Disk Size in GiB (min. 16 recommended)"
  vm_prompt_disk_cache "none"
  vm_prompt_hostname "moonlight"
  vm_prompt_cpu_model "host"
  vm_prompt_cpu_cores "2"
  vm_prompt_ram "2048"
  vm_prompt_bridge "vmbr0"
  vm_prompt_mac "$GEN_MAC"
  vm_prompt_vlan
  vm_prompt_mtu
  vm_prompt_keyboard
  vm_prompt_verbose "no"
  vm_prompt_start_vm "yes"

  if vm_confirm_advanced_settings "Ready to create a Moonlight VM?"; then
    echo -e "${CREATING}${BOLD}${DGN}Creating a Moonlight VM using the above advanced settings${CL}"
  else
    header_info
    echo -e "${ADVANCED}${BOLD}${RD}Using Advanced Settings${CL}"
    advanced_settings
  fi
}

vm_start_script "Use Default Settings?\n\nDefaults:\n• 2 CPU Cores\n• 2 GB RAM\n• 16 GB Disk" 13 58
if [[ "${MACHINE_TYPE:-}" != q35 ]]; then
  msg_error "Moonlight VMs require the q35 machine type."
  exit 1
fi
CLOUDINIT_REQUIRED=1
CLOUDINIT_DEFAULT_USER="debian"
vm_prompt_cloud_init "debian"
if [[ "$USE_CLOUD_INIT" != "yes" ]]; then
  msg_error "Moonlight needs a Cloud-Init user for the graphical session."
  exit 1
fi
CLOUDINIT_USER="${CLOUDINIT_USER:-debian}"
if [[ "$CLOUDINIT_USER" == "root" ]] || [[ ! "$CLOUDINIT_USER" =~ ^[a-z_][a-z0-9_-]*$ ]] || ((${#CLOUDINIT_USER} > 32)); then
  msg_error "Refusing Cloud-Init user '${CLOUDINIT_USER}': the desktop needs a non-root Unix username."
  exit 1
fi
select_client_options
select_passthrough
post_to_api_vm

vm_select_storage "$HN"
vm_define_disk_references 2

msg_info "Resolving the Moonlight release"
if ! vm_release_asset github moonlight-stream/moonlight-qt '^Moonlight-.*-x86_64\.AppImage$'; then
  exit 1
fi
if [[ -z "${VM_RELEASE_SHA256:-}" ]]; then
  msg_error "Moonlight release ${VM_RELEASE_TAG} publishes no digest; refusing an unverified download."
  exit 1
fi
APPIMAGE_FILE="$TEMP_DIR/$VM_RELEASE_ASSET"
vm_fetch_image "$VM_RELEASE_URL" "$APPIMAGE_FILE" --min-bytes $((10 * 1024 * 1024)) --sha256 "$VM_RELEASE_SHA256" || exit 115

URL="https://cloud.debian.org/images/cloud/trixie/latest/debian-13-generic-amd64.qcow2"

msg_info "Retrieving the URL for the Debian 13 Cloud Image"
msg_ok "${CL}${BL}${URL}${CL}"

CACHE_FILE="$(vm_image_cache_path "$URL")"
MIN_IMAGE_BYTES=$((100 * 1024 * 1024))
vm_fetch_image "$URL" "$CACHE_FILE" --cache --min-bytes "$MIN_IMAGE_BYTES" || exit 115

WORK_FILE="$TEMP_DIR/moonlight.qcow2"
cp "$CACHE_FILE" "$WORK_FILE"

msg_info "Installing prerequisites in image"
if vm_customize "Moonlight prerequisites" "$WORK_FILE" --install "qemu-guest-agent,curl,ca-certificates"; then
  msg_ok "Installed prerequisites"
else
  msg_warn "Package pre-install failed; the first boot installs them instead."
fi

vm_customize "Moonlight AppImage" "$WORK_FILE" \
  --mkdir /opt/moonlight \
  --upload "${APPIMAGE_FILE}:/opt/moonlight/${VM_RELEASE_ASSET}" \
  --chmod "0755:/opt/moonlight/${VM_RELEASE_ASSET}" || exit 1

vm_prepare_cloud_image "$WORK_FILE" "$HN" || true

MOONLIGHT_SETUP_TMP="$TEMP_DIR/moonlight-setup.sh"
cat >"$MOONLIGHT_SETUP_TMP" <<FIRSTBOOT
#!/usr/bin/env bash
set -Eeuo pipefail
export DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a
exec >> /var/log/moonlight-setup.log 2>&1

GUEST_USER="${CLOUDINIT_USER}"
AUTOSTART="${VM_CLIENT_AUTOSTART}"
AUTOLOGIN="${VM_DESKTOP_AUTOLOGIN}"

echo "[\$(date)] Starting Moonlight setup for \$GUEST_USER"

if [ -f /etc/apt/sources.list.d/debian.sources ]; then
  grep -q non-free-firmware /etc/apt/sources.list.d/debian.sources ||
    sed -i 's/^Components:.*/& non-free-firmware/' /etc/apt/sources.list.d/debian.sources
else
  grep -q non-free-firmware /etc/apt/sources.list 2>/dev/null ||
    sed -i '/^deb / s/\$/ non-free-firmware/' /etc/apt/sources.list
fi

apt -o Acquire::Retries=3 update

apt install -y \\
  qemu-guest-agent curl ca-certificates \\
  xorg xfce4 lightdm lightdm-gtk-greeter dbus-x11 polkitd \\
  pipewire wireplumber pipewire-pulse pipewire-alsa \\
  mesa-va-drivers mesa-vulkan-drivers intel-media-va-driver i965-va-driver \\
  firmware-amd-graphics firmware-intel-graphics firmware-misc-nonfree firmware-sof-signed vainfo vulkan-tools

systemctl enable --now qemu-guest-agent
getent group render >/dev/null || groupadd -r render
usermod -aG video,render "\$GUEST_USER"
systemctl --global enable pipewire.socket pipewire-pulse.socket wireplumber.service

if [ ! -x /opt/moonlight/squashfs-root/AppRun ]; then
  cd /opt/moonlight
  ./"${VM_RELEASE_ASSET}" --appimage-extract
  rm -f ./*.AppImage
fi
cat >/opt/moonlight/version.txt <<'VERSION'
${VM_RELEASE_VERSION}
VERSION

cat > /usr/local/bin/moonlight <<'LAUNCHER'
#!/bin/sh
exec /opt/moonlight/squashfs-root/AppRun "\$@"
LAUNCHER
chmod 0755 /usr/local/bin/moonlight

cat > /usr/share/applications/com.moonlight_stream.Moonlight.desktop <<'DESKTOP'
[Desktop Entry]
Name=Moonlight
Comment=Stream games and other applications from another PC running Sunshine or GeForce Experience
Exec=/opt/moonlight/squashfs-root/AppRun
Icon=moonlight
Terminal=false
Type=Application
Categories=Game;Network;RemoteAccess;
Keywords=nvidia;gamestream;stream;sunshine;remote play;
DESKTOP

install -m 0644 -D /opt/moonlight/squashfs-root/moonlight.svg /usr/share/icons/hicolor/scalable/apps/moonlight.svg
gtk-update-icon-cache -f /usr/share/icons/hicolor 2>/dev/null || true

if [ "\$AUTOSTART" = yes ]; then
  install -m 0644 -D /usr/share/applications/com.moonlight_stream.Moonlight.desktop "/home/\$GUEST_USER/.config/autostart/com.moonlight_stream.Moonlight.desktop"
  chown "\$GUEST_USER:\$GUEST_USER" "/home/\$GUEST_USER/.config"
  chown -R "\$GUEST_USER:\$GUEST_USER" "/home/\$GUEST_USER/.config/autostart"
fi

if [ "\$AUTOLOGIN" = yes ]; then
  mkdir -p /etc/lightdm/lightdm.conf.d
  cat > /etc/lightdm/lightdm.conf.d/12-autologin.conf <<'LIGHTDM'
[Seat:*]
autologin-user=${CLOUDINIT_USER}
autologin-user-timeout=0
LIGHTDM
fi

systemctl enable --now lightdm
systemctl set-default graphical.target
echo "[\$(date)] Moonlight setup complete"
FIRSTBOOT

vm_firstboot_unit "$WORK_FILE" moonlight-setup "$MOONLIGHT_SETUP_TMP" \
  --description "Moonlight desktop first boot installation" \
  --cloud-init yes || exit 1

vm_claim_vmid
msg_info "Creating a Debian 13 Moonlight VM"
qm create "$VMID" -agent 1${MACHINE} -tablet 0 -bios ovmf${CPU_TYPE} -cores "$CORE_COUNT" -memory "$RAM_SIZE" \
  -name "$HN" -tags community-script,moonlight -net0 "virtio,bridge=$BRG,macaddr=$MAC$VLAN$MTU" -onboot 1 -ostype l26 -scsihw virtio-scsi-pci
vm_mark_created

vm_alloc_efi_disk "$DISK0"
vm_import_disk "$VMID" "$WORK_FILE" "$STORAGE"

DISK_OPTIONS="${DISK_CACHE}${THIN}"
DISK_OPTIONS="${DISK_OPTIONS%,}"
ROOT_DISK="$VM_IMPORTED_DISK"
[[ -n "$DISK_OPTIONS" ]] && ROOT_DISK="${ROOT_DISK},${DISK_OPTIONS}"

qm set "$VMID" \
  --efidisk0 "${DISK0_REF}${FORMAT}" \
  --scsi0 "$ROOT_DISK" \
  --boot order=scsi0 \
  --serial0 socket >/dev/null
vm_resize_disk "scsi0" "$DISK_SIZE"
set_description

vm_provision "$VMID"
if [[ -n "${CLOUDINIT_SSH_KEYS:-}" ]]; then
  $STD qm set "$VMID" --sshkeys "$CLOUDINIT_SSH_KEYS"
fi

msg_ok "Created a Debian 13 Moonlight VM ${CL}${BL}(${HN})"
attach_passthrough
vm_start_vm "Moonlight VM"
vm_wait_for_ip 120 || true

display_cloud_init_info "$VMID" "$HN"

vm_print_summary \
  "GPU=${GPU_SLOT:-not assigned}" \
  "OS=Debian 13 (Trixie)" \
  "Moonlight=${VM_RELEASE_VERSION} (installs on first boot)" \
  "Desktop=Xfce + LightDM (user ${CLOUDINIT_USER})" \
  "USB=${VM_USB_PORTS:-not assigned}" \
  "Autostart=${VM_CLIENT_AUTOSTART}" \
  "Autologin=${VM_DESKTOP_AUTOLOGIN}" \
  "Pairing=In the Moonlight UI (enter the PIN in Sunshine)" \
  "Documentation=https://moonlight-stream.org/"
vm_next_steps \
  "Creating the VM does not mean the guest setup finished: the desktop and Moonlight install on first boot; follow it with: tail -f /var/log/moonlight-setup.log (unit: systemctl status moonlight-setup)." \
  "After the first boot completes, reboot the guest once before judging GPU behavior: firmware installed that late is picked up on the next boot. No host reboot is needed." \
  "Log in on the GPU-connected monitor as ${CLOUDINIT_USER} (noVNC works only without GPU assignment) with the Cloud-Init password (or straight into the desktop when autologin is on) and pair from the Moonlight UI: add the Sunshine host, then enter the PIN shown here in Sunshine." \
  "For a capable display and decoder, select 3840x2160 at 60 FPS and HEVC in Moonlight. Select the guest HDMI/DP or passed-through USB audio output and check the performance overlay." \
  "A passed-through GPU is assigned through the wizard device options; NVIDIA cards additionally need the vendor driver installed in the guest as a follow-up."
vm_finish "VM created. Moonlight and the desktop install in the VM on first boot."
