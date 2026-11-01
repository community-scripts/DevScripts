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
  local address="${VM_GPU_PCI:-}" device member class config value slot driver
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
  [[ -e "$device/iommu_group" ]] || {
    msg_error "No IOMMU group for $address. Enable VT-d/AMD-Vi in firmware and prepare PCI passthrough first: https://pve.proxmox.com/wiki/PCI_Passthrough"
    return 1
  }
  [[ ! -r "$device/boot_vga" || "$(<"$device/boot_vga")" != 1 || "${VM_ALLOW_BOOT_GPU:-no}" == yes ]] || {
    msg_error "$address is the host boot display. Deliberate use requires VM_ALLOW_BOOT_GPU=yes and an independent SSH management connection."
    return 1
  }
  driver="$(readlink "$device/driver" 2>/dev/null || true)"
  [[ "${driver##*/}" == vfio-pci ]] || {
    msg_error "$address must already use vfio-pci. Prepare this specific device using the Proxmox PCI passthrough guide, or choose no GPU. Host drivers and boot settings are not changed here."
    return 1
  }
  for member in "$device"/iommu_group/devices/*; do
    [[ -r "$member/class" ]] || return 1
    class="$(<"$member/class")"
    [[ "${member##*/}" == "$slot".* || "$class" == 0x0604* ]] || {
      msg_error "IOMMU group also contains ${member##*/}. Select an isolated GPU; ACS overrides are not configured."
      return 1
    }
    [[ "$class" == 0x0604* ]] && continue
    driver="$(readlink "$member/driver" 2>/dev/null || true)"
    [[ "${driver##*/}" == vfio-pci ]] || {
      msg_error "IOMMU group member ${member##*/} must also use vfio-pci."
      return 1
    }
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
  GPU_SLOT="$address"
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
    vm_dialog radiolist "GPU PASSTHROUGH" "Select one prepared display function. Other PCI functions are not attached. No GPU is selected automatically." 18 90 8 "${choices[@]}" || exit_script
    VM_GPU_PCI="$VM_DIALOG_RESULT"
  fi
  address="${VM_GPU_PCI:-none}"
  [[ "$address" == ????:??:??.? ]] || address="0000:$address"
  if [[ -z "${VM_ALLOW_BOOT_GPU:-}" && "${VM_UNATTENDED:-0}" != 1 &&
    -r "/sys/bus/pci/devices/$address/boot_vga" && "$(<"/sys/bus/pci/devices/$address/boot_vga")" == 1 ]]; then
    vm_dialog yesno "HOST BOOT GPU" "This GPU is the host boot display. Passing it through removes the local host console. Continue only with working SSH management and an intentionally VFIO-bound GPU. Use this boot GPU?" 13 80 || exit_script
    VM_ALLOW_BOOT_GPU=yes
  fi
  [[ "${VM_ALLOW_BOOT_GPU:-no}" =~ ^(yes|no)$ ]] || { msg_error "VM_ALLOW_BOOT_GPU must be yes or no."; return 1; }
  validate_gpu_passthrough || return 1
  if [[ -n "$GPU_SLOT" && -r "/sys/bus/pci/devices/$GPU_SLOT/vendor" ]] &&
    [[ "$(<"/sys/bus/pci/devices/$GPU_SLOT/vendor")" == 0x10de ]]; then
    msg_warn "Install a compatible NVIDIA driver inside the guest before testing hardware encoding/decoding; this installer stages AMD/Intel Mesa drivers."
  fi
  if [[ -z "${VM_RAVEN_RESET_GUARD:-}" && "${VM_UNATTENDED:-0}" != 1 && -n "$GPU_SLOT" &&
    "$(cat "/sys/bus/pci/devices/$GPU_SLOT/vendor")" == 0x1002 &&
    "$(cat "/sys/bus/pci/devices/$GPU_SLOT/device")" == 0x15dd ]]; then
    vm_dialog radiolist "RAVEN RIDGE RESET GUARD" "Optional workaround for AMD 1002:15dd: disable this display function's PCI reset methods now and before VM autostart on host boot. This persists as a host systemd service and does not guarantee all restart scenarios." 16 86 2 \
      no "Keep the host reset behavior" ON yes "Install this device-specific workaround" OFF || exit_script
    VM_RAVEN_RESET_GUARD="$VM_DIALOG_RESULT"
  fi
  VM_RAVEN_RESET_GUARD="${VM_RAVEN_RESET_GUARD:-no}"
  validate_raven_reset_guard || return 1
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
      summary="Dedicated display function: ${GPU_SLOT:-none}\nUSB ports: ${VM_USB_PORTS:-none}\nRaven Ridge reset guard: $VM_RAVEN_RESET_GUARD\n"
      if [[ -n "$GPU_SLOT" ]]; then
        summary+="\n$(lspci -D -s "$GPU_SLOT" -nn)"
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
    qm set "$VMID" --hostpci0 "$GPU_SLOT,pcie=1" --vga serial0 >/dev/null
  fi
  for index in "${!USB_PORTS[@]}"; do
    qm set "$VMID" "--usb$index" "host=${USB_PORTS[$index]},usb3=1" >/dev/null
  done
}

function validate_raven_reset_guard() {
  [[ "$VM_RAVEN_RESET_GUARD" =~ ^(yes|no)$ ]] || { msg_error "VM_RAVEN_RESET_GUARD must be yes or no."; return 1; }
  [[ "$VM_RAVEN_RESET_GUARD" == yes ]] || return 0
  [[ -n "$GPU_SLOT" && -r "/sys/bus/pci/devices/$GPU_SLOT/reset_method" &&
    "$(cat "/sys/bus/pci/devices/$GPU_SLOT/vendor")" == 0x1002 &&
    "$(cat "/sys/bus/pci/devices/$GPU_SLOT/device")" == 0x15dd ]] || {
    msg_error "The reset guard requires an explicitly selected AMD Raven Ridge 1002:15dd display function with reset_method support."
    return 1
  }
}

function install_raven_reset_guard() {
  [[ "$VM_RAVEN_RESET_GUARD" == yes ]] || return 0
  validate_raven_reset_guard || return 1
  local script="/usr/local/sbin/moonlight-raven-reset-$VMID" unit="moonlight-raven-reset-$VMID.service"
  [[ ! -e "$script" && ! -e "/etc/systemd/system/$unit" ]] || {
    msg_error "A Moonlight reset guard already exists for VM $VMID; inspect it before retrying."
    return 1
  }
  msg_info "Installing Moonlight's Raven Ridge reset guard"
  cat >"$script" <<GUARD
#!/bin/sh
set -eu
DEVICE="/sys/bus/pci/devices/$GPU_SLOT"
test "\$(cat "\$DEVICE/vendor")" = 0x1002
test "\$(cat "\$DEVICE/device")" = 0x15dd
test "\$(basename "\$(readlink "\$DEVICE/driver")")" = vfio-pci
test -f "\$DEVICE/reset_method"
if test -n "\$(cat "\$DEVICE/reset_method")"; then
  printf '\\n' >"\$DEVICE/reset_method"
fi
test -z "\$(cat "\$DEVICE/reset_method")"
GUARD
  chmod 0755 "$script"
  cat >"/etc/systemd/system/$unit" <<UNIT
[Unit]
Description=Moonlight Raven Ridge PCI reset guard ($GPU_SLOT)
After=systemd-udev-trigger.service
Before=pve-guests.service

[Service]
Type=oneshot
ExecStart=$script
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
UNIT
  systemctl enable --now "$unit"
  msg_ok "Installed Moonlight's Raven Ridge reset guard"
}

function default_settings() {
  VMID=$(get_valid_nextid)
  vm_apply_machine_type "q35"
  DISK_SIZE="16G"
  DISK_CACHE=""
  HN="moonlight"
  CPU_TYPE=" -cpu host"
  CORE_COUNT="4"
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
  vm_prompt_cpu_cores "4"
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

vm_start_script "Use Default Settings?\n\nDefaults:\n• 4 CPU Cores\n• 2 GB RAM\n• 16 GB Disk" 13 58
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

vm_latest_from_index 'https://github.com/Bash-it/bash-it/releases/latest' '/Bash-it/bash-it/releases/tag/\Kv[0-9]+\.[0-9]+\.[0-9]+' || exit 1
BASHIT_ARCHIVE="$TEMP_DIR/bash-it.tar.gz"
vm_fetch_image "https://github.com/Bash-it/bash-it/archive/refs/tags/$VM_INDEX_LATEST.tar.gz" "$BASHIT_ARCHIVE" --min-bytes $((100 * 1024)) || exit 115

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
  --upload "${BASHIT_ARCHIVE}:/opt/moonlight/bash-it.tar.gz" \
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

echo "[\$(date '+%F %T')] Starting Moonlight setup for \$GUEST_USER"
for _ in {1..30}; do
  getent hosts deb.debian.org >/dev/null 2>&1 && break
  sleep 2
done

for component in contrib non-free non-free-firmware; do
  if [[ -f /etc/apt/sources.list.d/debian.sources ]]; then
    sed -i -E "/^Components:/ { /(^|[[:space:]])\${component}([[:space:]]|\$)/! s/\$/ \${component}/; }" /etc/apt/sources.list.d/debian.sources
  fi
  if [[ -f /etc/apt/sources.list ]]; then
    sed -i -E "/^deb / { /(^|[[:space:]])\${component}([[:space:]]|\$)/! s/\$/ \${component}/; }" /etc/apt/sources.list
  fi
done

apt -o Acquire::Retries=3 update
apt install -y \
  qemu-guest-agent curl ca-certificates libfuse2t64 \
  xserver-xorg-core xserver-xorg-input-libinput xserver-xorg-video-amdgpu \
  xinit openbox x11-xserver-utils wmctrl xauth dbus-user-session unclutter-xfixes adwaita-icon-theme fonts-dejavu-core git \
  pipewire wireplumber pipewire-pulse pipewire-alsa \
  mesa-va-drivers mesa-vulkan-drivers intel-media-va-driver \
  firmware-amd-graphics firmware-intel-graphics firmware-misc-nonfree firmware-sof-signed vainfo vulkan-tools

systemctl enable --now qemu-guest-agent
getent group render >/dev/null || groupadd -r render
usermod -s /bin/bash -aG audio,video,render,input,plugdev "\$GUEST_USER"
systemctl --global enable pipewire.socket pipewire-pulse.socket wireplumber.service

USER_HOME="\$(getent passwd "\$GUEST_USER" | cut -d: -f6)"
if [[ -z "\$USER_HOME" || ! -d "\$USER_HOME" ]]; then
  echo "Home directory for \$GUEST_USER is missing" >&2
  exit 1
fi

STAGED_APPIMAGE="/opt/moonlight/${VM_RELEASE_ASSET}"
APPIMAGE=/opt/moonlight/Moonlight.AppImage
if [[ ! -f \$APPIMAGE && -f \$STAGED_APPIMAGE && \$STAGED_APPIMAGE != "\$APPIMAGE" ]]; then
  mv "\$STAGED_APPIMAGE" "\$APPIMAGE"
fi
if [[ ! -f \$APPIMAGE ]]; then
  echo "Moonlight AppImage is missing from /opt/moonlight" >&2
  exit 1
fi
chmod 0755 "\$APPIMAGE"
cat >/opt/moonlight/version.txt <<'VERSION'
${VM_RELEASE_VERSION}
VERSION

if [[ ! -f /etc/moonlight-kiosk.conf ]]; then
  cat > /etc/moonlight-kiosk.conf <<'KCONF'
# Moonlight kiosk defaults read by /usr/local/bin/moonlight.
# Edit values here, or use MOONLIGHT_KIOSK_CONF to select a different file.
PREFER_VULKAN=1
QT_SCALE_FACTOR=2.5
KCONF
fi

cat > /usr/local/bin/moonlight <<'LAUNCHER'
#!/bin/sh
set -u
_MOONLIGHT_CONF="\${MOONLIGHT_KIOSK_CONF:-/etc/moonlight-kiosk.conf}"
if [ -r "\$_MOONLIGHT_CONF" ]; then
  . "\$_MOONLIGHT_CONF"
fi
: "\${PREFER_VULKAN:=1}"
: "\${QT_SCALE_FACTOR:=2.5}"
export PREFER_VULKAN QT_SCALE_FACTOR
if [ -z "\${LIBVA_DRIVER_NAME:-}" ]; then
  for _drv in /sys/bus/pci/devices/*/driver; do
    _driver=\$(readlink "\$_drv" 2>/dev/null || true)
    if [ "\${_driver##*/}" = amdgpu ]; then
      LIBVA_DRIVER_NAME=radeonsi
      export LIBVA_DRIVER_NAME
      break
    fi
  done
  unset _drv _driver
fi
exec /opt/moonlight/Moonlight.AppImage "\$@"
LAUNCHER
chmod 0755 /usr/local/bin/moonlight

cat > /usr/share/applications/com.moonlight_stream.Moonlight.desktop <<'DESKTOP'
[Desktop Entry]
Name=Moonlight
Comment=Stream games and other applications from another PC running Sunshine or GeForce Experience
Exec=/usr/local/bin/moonlight
Icon=moonlight
Terminal=false
Type=Application
Categories=Game;Network;RemoteAccess;
Keywords=nvidia;gamestream;stream;sunshine;remote play;
DESKTOP

OPENBOX_DIR="\$USER_HOME/.config/openbox"
mkdir -p "\$OPENBOX_DIR"
if [[ -f \$OPENBOX_DIR/autostart && ! -e \$OPENBOX_DIR/autostart.bak ]]; then
  cp -a "\$OPENBOX_DIR/autostart" "\$OPENBOX_DIR/autostart.bak"
fi
cat > "\$OPENBOX_DIR/autostart" <<'AUTOSTART'
#!/bin/sh
# Managed by moonlight-setup: Moonlight kiosk session (original backed up as autostart.bak).
if command -v xset >/dev/null 2>&1; then
  xset s off
  xset s noblank
  xset -dpms
fi
if command -v xrandr >/dev/null 2>&1; then
  _output=\$(xrandr --query 2>/dev/null | awk '\$2 == "connected" {print \$1; exit}')
  if [ -n "\${_output}" ]; then
    if xrandr --query 2>/dev/null | awk -v out="\${_output}" '
      \$1 == out && \$2 == "connected" {want = 1; next}
      /^[A-Za-z].*(connected|disconnected)/ {want = 0}
      want && \$1 == "3840x2160" && / 60\.00([*+]| |\$)/ {found = 1}
      END {exit !found}'; then
      xrandr --output "\${_output}" --mode 3840x2160 --rate 60 2>/dev/null || true
    fi
  fi
  unset _output
fi
if command -v unclutter >/dev/null 2>&1; then
  unclutter --timeout 1 --start-hidden --fork
fi
AUTOSTART
if [[ \$AUTOSTART == yes ]]; then
  cat >> "\$OPENBOX_DIR/autostart" <<'AUTOSTART_MOONLIGHT'
mkdir -p "\$HOME/.local/state"
( while :; do
  /usr/local/bin/moonlight >>"\$HOME/.local/state/moonlight-kiosk.log" 2>&1
  sleep 3
done ) &
if command -v wmctrl >/dev/null 2>&1; then
  ( while :; do
    wmctrl -r Moonlight -b add,fullscreen 2>/dev/null || true
    sleep 3
  done ) &
fi
AUTOSTART_MOONLIGHT
fi
chmod 0755 "\$OPENBOX_DIR/autostart"
chown -R "\$GUEST_USER:\$GUEST_USER" "\$OPENBOX_DIR"

if [[ -f \$USER_HOME/.xinitrc && ! -e \$USER_HOME/.xinitrc.bak ]]; then
  cp -a "\$USER_HOME/.xinitrc" "\$USER_HOME/.xinitrc.bak"
fi
cat > "\$USER_HOME/.xinitrc" <<'XINITRC'
#!/bin/sh
# Managed by moonlight-setup: minimal X session for the Moonlight kiosk.
export XCURSOR_THEME=Adwaita
export XCURSOR_SIZE=64
if [ -r "\$HOME/.Xresources" ]; then
  xrdb -merge "\$HOME/.Xresources"
fi
exec openbox-session
XINITRC
chmod 0755 "\$USER_HOME/.xinitrc"
chown "\$GUEST_USER:\$GUEST_USER" "\$USER_HOME/.xinitrc"

KIOSK_MARKER="# moonlight-kiosk: start X on tty1"
if [[ -f \$USER_HOME/.bash_profile ]] && ! grep -qF "\$KIOSK_MARKER" "\$USER_HOME/.bash_profile"; then
  [[ -e \$USER_HOME/.bash_profile.bak ]] || cp -a "\$USER_HOME/.bash_profile" "\$USER_HOME/.bash_profile.bak"
fi
if [[ ! -f \$USER_HOME/.bash_profile ]]; then
  cat > "\$USER_HOME/.bash_profile" <<'PROFILE'
# Created by moonlight-setup: keep the default login chain, then start the kiosk on tty1.
if [ -r "\$HOME/.profile" ]; then
  . "\$HOME/.profile"
fi
PROFILE
fi
if ! grep -qF "\$KIOSK_MARKER" "\$USER_HOME/.bash_profile"; then
  cat >> "\$USER_HOME/.bash_profile" <<'PROFILE_KIOSK'
# moonlight-kiosk: start X on tty1
if [ -z "\${DISPLAY:-}" ] && [ "\$(tty)" = /dev/tty1 ]; then
  exec startx -- -nolisten tcp
fi
PROFILE_KIOSK
fi
chown "\$GUEST_USER:\$GUEST_USER" "\$USER_HOME/.bash_profile"

BASH_IT_SRC=/opt/moonlight/bash-it.tar.gz
BASH_IT_DIR="\$USER_HOME/.bash_it"
if [[ ! -d \$BASH_IT_DIR ]]; then
  if [[ ! -f \$BASH_IT_SRC ]]; then
    echo "Bash-it source \$BASH_IT_SRC is missing" >&2
    exit 1
  fi
  BASH_IT_STAGE=\$(mktemp -d "\$USER_HOME/.bash_it.XXXXXX")
  tar -xzf "\$BASH_IT_SRC" -C "\$BASH_IT_STAGE" --strip-components=1
  chown -R "\$GUEST_USER:\$GUEST_USER" "\$BASH_IT_STAGE"
  mv "\$BASH_IT_STAGE" "\$BASH_IT_DIR"
fi
if [[ ! -f \$BASH_IT_DIR/install.sh ]]; then
  echo "Bash-it installer is missing from \$BASH_IT_DIR" >&2
  exit 1
fi
runuser -u "\$GUEST_USER" -- env HOME="\$USER_HOME" BASH_IT="\$BASH_IT_DIR" bash "\$BASH_IT_DIR/install.sh" --silent --no-modify-config
BASHIT_MARKER="# moonlight-kiosk: Bash-it with the pure theme"
if [[ -f \$USER_HOME/.bashrc ]] && ! grep -qF "\$BASHIT_MARKER" "\$USER_HOME/.bashrc"; then
  [[ -e \$USER_HOME/.bashrc.bak ]] || cp -a "\$USER_HOME/.bashrc" "\$USER_HOME/.bashrc.bak"
fi
[[ -f \$USER_HOME/.bashrc ]] || touch "\$USER_HOME/.bashrc"
if ! grep -qF "\$BASHIT_MARKER" "\$USER_HOME/.bashrc"; then
  cat >> "\$USER_HOME/.bashrc" <<'BASHRC_SNIPPET'
# moonlight-kiosk: Bash-it with the pure theme
if [ -d "\$HOME/.bash_it" ]; then
  export BASH_IT="\$HOME/.bash_it"
  export BASH_IT_THEME=pure
  if [ -r "\$BASH_IT/bash_it.sh" ]; then
    . "\$BASH_IT/bash_it.sh"
  fi
fi
BASHRC_SNIPPET
fi
chown "\$GUEST_USER:\$GUEST_USER" "\$USER_HOME/.bashrc"

GETTY_DROPIN=/etc/systemd/system/getty@tty1.service.d/12-autologin.conf
if [[ \$AUTOLOGIN == yes ]]; then
  mkdir -p /etc/systemd/system/getty@tty1.service.d
  cat > "\$GETTY_DROPIN" <<'GETTY'
# Managed by moonlight-setup: opt-in console autologin for the kiosk user.
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin ${CLOUDINIT_USER} --noclear %I \$TERM
GETTY
  systemctl daemon-reload
elif [[ -f \$GETTY_DROPIN ]] && grep -q "Managed by moonlight-setup" "\$GETTY_DROPIN" 2>/dev/null; then
  rm -f "\$GETTY_DROPIN"
  systemctl daemon-reload
fi
systemctl enable getty@tty1.service

mkdir -p /etc/default/grub.d
cat > /etc/default/grub.d/60-moonlight-kiosk.cfg <<'GRUB'
# Managed by moonlight-setup: keep video and serial consoles, disable console blanking.
GRUB_CMDLINE_LINUX="\${GRUB_CMDLINE_LINUX:+\$GRUB_CMDLINE_LINUX }console=tty0 console=ttyS0,115200 consoleblank=0"
GRUB
if command -v update-grub >/dev/null 2>&1; then
  update-grub
fi

systemctl enable serial-getty@ttyS0.service
systemctl set-default multi-user.target
echo "[\$(date '+%F %T')] Moonlight setup complete"
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
install_raven_reset_guard
vm_start_vm "Moonlight VM"
vm_wait_for_ip 120 || true

display_cloud_init_info "$VMID" "$HN"

vm_print_summary \
  "GPU=${GPU_SLOT:-not assigned}" \
  "OS=Debian 13 (Trixie)" \
  "Moonlight=${VM_RELEASE_VERSION} (installs on first boot)" \
  "Session=tty1 -> Xorg -> Openbox -> Moonlight (user ${CLOUDINIT_USER})" \
  "USB=${VM_USB_PORTS:-not assigned}" \
  "Autostart=${VM_CLIENT_AUTOSTART}" \
  "Autologin=${VM_DESKTOP_AUTOLOGIN}" \
  "RavenResetGuard=${VM_RAVEN_RESET_GUARD}" \
  "Pairing=In the Moonlight UI (enter the PIN in Sunshine)" \
  "Documentation=https://moonlight-stream.org/"
vm_next_steps \
  "Wait for Moonlight setup: journalctl -u moonlight-setup -f (log: /var/log/moonlight-setup.log). Success marker: /var/lib/community-scripts/moonlight-setup.done." \
  "After the first boot completes, reboot the guest once before judging GPU behavior: firmware installed that late is picked up on the next boot. No host reboot is needed." \
  "On tty1, sign in as ${CLOUDINIT_USER} to start the kiosk, or select VM_DESKTOP_AUTOLOGIN=yes for appliance use. SSH and Proxmox's serial console remain text-only management sessions. GPU output needs a connected monitor/TV." \
  "In the Moonlight GUI, add the Sunshine host and enter the displayed PIN in Sunshine. Select 3840x2160, 60 FPS and HEVC; verify hardware decoding, controller navigation in the GUI/stream and actual received FPS in the performance overlay." \
  "Kiosk configuration: /etc/moonlight-kiosk.conf. Launcher: /usr/local/bin/moonlight. Session log: ~/.local/state/moonlight-kiosk.log. The display prefers an available 4K60 mode; this does not guarantee 60 received stream frames per second." \
  "A passed-through GPU is assigned through the wizard device options; NVIDIA cards additionally need the vendor driver installed in the guest as a follow-up."
if [[ "$VM_RAVEN_RESET_GUARD" == yes ]]; then
  vm_next_steps "Host workaround: moonlight-raven-reset-$VMID.service disables resets only for $GPU_SLOT. Check it after a host reboot; it is not a general AMD reset fix. To remove it, disable that unit and remove its unit file and /usr/local/sbin/moonlight-raven-reset-$VMID; the next host reboot restores kernel defaults."
fi
vm_finish "VM created. Moonlight kiosk installation continues in the VM on first boot."
