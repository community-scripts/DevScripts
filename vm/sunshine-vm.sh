#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Tomblarom
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://app.lizardbyte.dev

COMMUNITY_SCRIPTS_URL="${COMMUNITY_SCRIPTS_URL:-https://raw.githubusercontent.com/community-scripts/DevScripts/main}"
source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/pve/vm-core.func")
load_functions

APP="Sunshine"
APP_TYPE="vm"
NSAPP="sunshine-vm"
var_os="debian"
var_version="13"
GEN_MAC=02:$(openssl rand -hex 5 | awk '{print toupper($0)}' | sed 's/\(..\)/\1:/g; s/.$//')
RANDOM_UUID="$(cat /proc/sys/kernel/random/uuid)"
METHOD=""
THIN="discard=on,ssd=1,"
USE_CLOUD_INIT="no"
CLOUDINIT_DEFAULT_USER="debian"
OS_LABEL="Debian 13 (Trixie)"
INSTALL_STEAM=""
INSTALL_DOLPHIN=""
INSTALL_PEGASUS=""
DESKTOP_AUTOLOGIN=""
SUNSHINE_TAG=""
SUNSHINE_FIRSTBOOT_MARKER=""

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
  DISK_SIZE="64G"
  DISK_CACHE=""
  HN="sunshine"
  CPU_TYPE=" -cpu host"
  CORE_COUNT="8"
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
  vm_prompt_disk_size "64G" "Set Disk Size in GiB (min. 64 recommended)"
  vm_prompt_disk_cache "none"
  vm_prompt_hostname "sunshine"
  vm_prompt_cpu_model "host"
  vm_prompt_cpu_cores "8"
  vm_prompt_ram "8192"
  vm_prompt_bridge "vmbr0"
  vm_prompt_mac "$GEN_MAC"
  vm_prompt_vlan
  vm_prompt_mtu
  vm_prompt_keyboard
  vm_prompt_verbose "no"
  vm_prompt_start_vm "yes"

  if vm_confirm_advanced_settings "Ready to create a Debian 13 Sunshine VM?"; then
    echo -e "${CREATING}${BOLD}${DGN}Creating a Debian 13 Sunshine VM using the above advanced settings${CL}"
  else
    header_info
    echo -e "${ADVANCED}${BOLD}${RD}Using Advanced Settings${CL}"
    advanced_settings
  fi
}

function select_components() {
  if [[ "${VM_UNATTENDED:-0}" == "1" ]]; then
    INSTALL_STEAM="${VM_INSTALL_STEAM:-yes}"
    INSTALL_DOLPHIN="${VM_INSTALL_DOLPHIN:-yes}"
    INSTALL_PEGASUS="${VM_INSTALL_PEGASUS:-no}"
    DESKTOP_AUTOLOGIN="${VM_DESKTOP_AUTOLOGIN:-no}"
  else
    if [[ -z "${VM_INSTALL_STEAM:-}" ]]; then
      if vm_dialog radiolist "STEAM" \
        "Install Steam from Debian packages? (adds contrib and i386)" 11 68 2 \
        "yes" "Install Steam" ON \
        "no" "Skip Steam" OFF; then
        INSTALL_STEAM="$VM_DIALOG_RESULT"
      else
        exit_script
      fi
    else
      INSTALL_STEAM="$VM_INSTALL_STEAM"
    fi
    if [[ -z "${VM_INSTALL_DOLPHIN:-}" ]]; then
      if vm_dialog radiolist "DOLPHIN" \
        "Install Dolphin (GameCube/Wii) from Debian packages?" 11 68 2 \
        "yes" "Install Dolphin" ON \
        "no" "Skip Dolphin" OFF; then
        INSTALL_DOLPHIN="$VM_DIALOG_RESULT"
      else
        exit_script
      fi
    else
      INSTALL_DOLPHIN="$VM_INSTALL_DOLPHIN"
    fi
    if [[ -z "${VM_INSTALL_PEGASUS:-}" ]]; then
      if vm_dialog radiolist "PEGASUS" \
        "Install Pegasus Frontend alpha from its continuous build?" 11 68 2 \
        "no" "Skip Pegasus" ON \
        "yes" "Install Pegasus (alpha)" OFF; then
        INSTALL_PEGASUS="$VM_DIALOG_RESULT"
      else
        exit_script
      fi
    else
      INSTALL_PEGASUS="$VM_INSTALL_PEGASUS"
    fi
    if [[ -z "${VM_DESKTOP_AUTOLOGIN:-}" ]]; then
      if vm_dialog radiolist "DESKTOP AUTOLOGIN" \
        "Log the debian user into Plasma automatically?" 11 68 2 \
        "no" "Ask for credentials" ON \
        "yes" "Autologin as debian" OFF; then
        DESKTOP_AUTOLOGIN="$VM_DIALOG_RESULT"
      else
        exit_script
      fi
    else
      DESKTOP_AUTOLOGIN="$VM_DESKTOP_AUTOLOGIN"
    fi
  fi

  local var
  for var in INSTALL_STEAM INSTALL_DOLPHIN INSTALL_PEGASUS DESKTOP_AUTOLOGIN; do
    if [[ "${!var}" != "yes" && "${!var}" != "no" ]]; then
      msg_error "Invalid ${var}=${!var} (expected yes or no)"
      exit 1
    fi
  done
  echo -e "${INFO}${BOLD}${DGN}Steam: ${BGN}${INSTALL_STEAM}${CL}"
  echo -e "${INFO}${BOLD}${DGN}Dolphin: ${BGN}${INSTALL_DOLPHIN}${CL}"
  echo -e "${INFO}${BOLD}${DGN}Pegasus: ${BGN}${INSTALL_PEGASUS}${CL}"
  echo -e "${INFO}${BOLD}${DGN}Desktop autologin: ${BGN}${DESKTOP_AUTOLOGIN}${CL}"
}

vm_start_script "Use Default Settings?\n\nDefaults:\n• 8 CPU Cores\n• 8 GB RAM\n• 64 GB Disk" 13 58
if [[ "${MACHINE_TYPE:-}" != "q35" ]]; then
  msg_error "Sunshine VMs require the q35 machine type (got '${MACHINE_TYPE:-unset}')"
  exit 1
fi
CLOUDINIT_REQUIRED=1
vm_prompt_cloud_init "debian"
if [[ "$USE_CLOUD_INIT" != "yes" ]]; then
  msg_error "Sunshine cloud images require Cloud-Init credentials."
  exit 1
fi
CLOUDINIT_USER="${CLOUDINIT_USER:-debian}"
if [[ "$CLOUDINIT_USER" == "root" ]] ||
  [[ ! "$CLOUDINIT_USER" =~ ^[a-z_][a-z0-9_-]*$ ]] ||
  ((${#CLOUDINIT_USER} > 32)); then
  msg_error "Invalid Cloud-Init user '${CLOUDINIT_USER}' (expected a non-root login name)"
  exit 1
fi
select_components
select_passthrough
post_to_api_vm

vm_select_storage "$HN"
vm_define_disk_references 2

URL="https://cloud.debian.org/images/cloud/trixie/latest/debian-13-generic-amd64.qcow2"

msg_info "Retrieving the URL for the ${OS_LABEL} Cloud Image"
msg_ok "${CL}${BL}${URL}${CL}"

CACHE_FILE="$(vm_image_cache_path "$URL")"
MIN_IMAGE_BYTES=$((100 * 1024 * 1024))
vm_fetch_image "$URL" "$CACHE_FILE" --cache --min-bytes "$MIN_IMAGE_BYTES" || exit 115

WORK_FILE="$TEMP_DIR/sunshine.qcow2"
cp "$CACHE_FILE" "$WORK_FILE"

SUNSHINE_PATTERN='^sunshine_.*[+]debiantrixie_amd64\.deb$'
msg_info "Resolving the Sunshine release"
if vm_release_asset github LizardByte/Sunshine "$SUNSHINE_PATTERN"; then
  SUNSHINE_TAG="$VM_RELEASE_TAG"
  SUNSHINE_DEB="$TEMP_DIR/$VM_RELEASE_ASSET"
  if [[ -z "${VM_RELEASE_SHA256:-}" ]]; then
    msg_error "Sunshine release ${VM_RELEASE_TAG} publishes no digest"
    exit 1
  fi
  vm_fetch_image "$VM_RELEASE_URL" "$SUNSHINE_DEB" --sha256 "$VM_RELEASE_SHA256" --min-bytes $((1024 * 1024)) || exit 115
  msg_ok "Staged ${VM_RELEASE_ASSET}"
else
  exit 1
fi

PEGASUS_DEB=""
if [[ "$INSTALL_PEGASUS" == "yes" ]]; then
  PEGASUS_PATTERN='^pegasus-frontend_.*_amd64\.deb$'
  msg_info "Resolving the Pegasus Frontend release"
  if vm_release_asset github mmatyas/pegasus-frontend "$PEGASUS_PATTERN" continuous; then
    PEGASUS_DEB="$TEMP_DIR/$VM_RELEASE_ASSET"
    if [[ -z "${VM_RELEASE_SHA256:-}" ]]; then
      msg_error "Pegasus Frontend release ${VM_RELEASE_TAG} publishes no digest"
      exit 1
    fi
    vm_fetch_image "$VM_RELEASE_URL" "$PEGASUS_DEB" --sha256 "$VM_RELEASE_SHA256" --min-bytes $((1024 * 1024)) || exit 115
    msg_ok "Staged ${VM_RELEASE_ASSET}"
  else
    exit 1
  fi
fi

STAGE_ARGS=(--mkdir /opt/community-scripts --upload "${SUNSHINE_DEB}:/opt/community-scripts/sunshine.deb")
if [[ -n "$PEGASUS_DEB" ]]; then
  STAGE_ARGS+=(--upload "${PEGASUS_DEB}:/opt/community-scripts/pegasus.deb")
fi
msg_info "Staging application packages in image"
vm_customize "Application packages" "$WORK_FILE" "${STAGE_ARGS[@]}" || exit 1
msg_ok "Staged application packages in image"

vm_prepare_cloud_image "$WORK_FILE" "$HN" || true

SUNSHINE_FIRSTBOOT_TMP="$TEMP_DIR/sunshine-firstboot.sh"
cat >"$SUNSHINE_FIRSTBOOT_TMP" <<FIRSTBOOT
#!/usr/bin/env bash
set -Eeuo pipefail
export DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a
exec >> /var/log/sunshine-firstboot.log 2>&1

echo "[\$(date '+%F %T')] Starting Sunshine first boot installation"
for _ in {1..30}; do
  getent hosts deb.debian.org >/dev/null 2>&1 && break
  sleep 2
done

GUEST_USER="${CLOUDINIT_USER}"
INSTALL_STEAM="${INSTALL_STEAM}"
INSTALL_DOLPHIN="${INSTALL_DOLPHIN}"
INSTALL_PEGASUS="${INSTALL_PEGASUS}"
DESKTOP_AUTOLOGIN="${DESKTOP_AUTOLOGIN}"

for component in contrib non-free non-free-firmware; do
  if [[ -f /etc/apt/sources.list.d/debian.sources ]]; then
    sed -i -E "/^Components:/ { /(^|[[:space:]])\${component}([[:space:]]|\$)/! s/\$/ \${component}/; }" /etc/apt/sources.list.d/debian.sources
  fi
  if [[ -f /etc/apt/sources.list ]]; then
    sed -i -E "/^deb / { /(^|[[:space:]])\${component}([[:space:]]|\$)/! s/\$/ \${component}/; }" /etc/apt/sources.list
  fi
done

apt update
apt install -y \\
  curl jq qemu-guest-agent \\
  kde-plasma-desktop sddm xwayland \\
  pipewire wireplumber pipewire-pulse pipewire-alsa libcap2-bin \\
  mesa-va-drivers mesa-vulkan-drivers intel-media-va-driver-non-free \\
  firmware-amd-graphics firmware-intel-graphics firmware-misc-nonfree \\
  vainfo vulkan-tools
systemctl enable --now qemu-guest-agent
systemctl --global enable pipewire.socket pipewire-pulse.socket wireplumber.service
systemctl set-default graphical.target

if [[ "\${INSTALL_STEAM}" == "yes" ]]; then
  dpkg --add-architecture i386
  apt update
  apt install -y mesa-vulkan-drivers libglx-mesa0:i386 mesa-vulkan-drivers:i386 libgl1-mesa-dri:i386 steam-installer
fi

apt install -y /opt/community-scripts/sunshine.deb
modprobe -a uinput uhid
getent group render >/dev/null || groupadd -r render
usermod -aG input,video,render "\${GUEST_USER}"

SUNSHINE_UNIT=""
for candidate in /usr/lib/systemd/user/app-dev.lizardbyte.app.Sunshine.service /usr/lib/systemd/user/sunshine.service; do
  if [[ -f "\${candidate}" ]]; then
    SUNSHINE_UNIT="\${candidate}"
    break
  fi
done
if [[ -n "\${SUNSHINE_UNIT}" ]]; then
  USER_WANTS="/home/\${GUEST_USER}/.config/systemd/user/graphical-session.target.wants"
  mkdir -p "\${USER_WANTS}"
  ln -sf "\${SUNSHINE_UNIT}" "\${USER_WANTS}/\$(basename "\${SUNSHINE_UNIT}")"
  chown -R "\${GUEST_USER}:\${GUEST_USER}" "/home/\${GUEST_USER}/.config"
else
  mkdir -p "/home/\${GUEST_USER}/.config/autostart"
  cat > "/home/\${GUEST_USER}/.config/autostart/sunshine.desktop" <<'DESKTOP'
[Desktop Entry]
Type=Application
Name=Sunshine
Exec=/usr/bin/sunshine
X-GNOME-Autostart-enabled=true
DESKTOP
  chown -R "\${GUEST_USER}:\${GUEST_USER}" "/home/\${GUEST_USER}/.config"
fi

if [[ "\${INSTALL_DOLPHIN}" == "yes" ]]; then
  apt install -y dolphin-emu
  DOLPHIN_GAMES="/home/\${GUEST_USER}/games/dolphin"
  mkdir -p "\${DOLPHIN_GAMES}"
  chown "\${GUEST_USER}:\${GUEST_USER}" "/home/\${GUEST_USER}/games" "\${DOLPHIN_GAMES}"
  if [[ ! -e "\${DOLPHIN_GAMES}/metadata.pegasus.txt" ]]; then
    cat > "\${DOLPHIN_GAMES}/metadata.pegasus.txt" <<'METADATA'
collection: Dolphin
extensions: iso, rvz, wbfs, ciso, gcm, wad, m3u
launch: /usr/games/dolphin-emu -b -e "{file.path}"
METADATA
    chown "\${GUEST_USER}:\${GUEST_USER}" "\${DOLPHIN_GAMES}/metadata.pegasus.txt"
  fi
fi

if [[ "\${INSTALL_PEGASUS}" == "yes" ]]; then
  apt install -y /opt/community-scripts/pegasus.deb
  if [[ "\${INSTALL_DOLPHIN}" == "yes" ]]; then
    PEGASUS_CONFIG="/home/\${GUEST_USER}/.config/pegasus-frontend"
    mkdir -p "\${PEGASUS_CONFIG}"
    if ! grep -Fxq "\${DOLPHIN_GAMES}" "\${PEGASUS_CONFIG}/game_dirs.txt" 2>/dev/null; then
      cat >>"\${PEGASUS_CONFIG}/game_dirs.txt" <<EOF
\${DOLPHIN_GAMES}
EOF
    fi
    chown -R "\${GUEST_USER}:\${GUEST_USER}" "\${PEGASUS_CONFIG}"
  fi
  SUNSHINE_CONFIG="/home/\${GUEST_USER}/.config/sunshine"
  mkdir -p "\${SUNSHINE_CONFIG}"
  if [[ ! -e "\${SUNSHINE_CONFIG}/apps.json" ]]; then
    cp /usr/share/sunshine/apps.json "\${SUNSHINE_CONFIG}/apps.json"
  fi
  jq -e 'type == "object" and (.apps | type == "array")' "\${SUNSHINE_CONFIG}/apps.json" >/dev/null
  APPS_TEMP="\$(mktemp "\${SUNSHINE_CONFIG}/apps.XXXXXX")"
  jq 'if any(.apps[]; .name == "Pegasus") then . else .apps += [{"name":"Pegasus", "cmd":"env QT_QPA_PLATFORM=xcb /usr/bin/pegasus-fe"}] end' \
    "\${SUNSHINE_CONFIG}/apps.json" >"\${APPS_TEMP}"
  chown "\${GUEST_USER}:\${GUEST_USER}" "\${SUNSHINE_CONFIG}" "\${APPS_TEMP}"
  chmod 600 "\${APPS_TEMP}"
  mv "\${APPS_TEMP}" "\${SUNSHINE_CONFIG}/apps.json"
fi

if [[ "\${DESKTOP_AUTOLOGIN}" == "yes" ]]; then
  mkdir -p /etc/sddm.conf.d
  for SESSION_FILE in /usr/share/wayland-sessions/plasma*.desktop; do
    [[ -f "\${SESSION_FILE}" ]] || { echo "Plasma Wayland session is missing"; exit 1; }
    cat > /etc/sddm.conf.d/autologin.conf <<EOF
[Autologin]
User=\${GUEST_USER}
Relogin=false
Session=\${SESSION_FILE##*/}
EOF
    break
  done
fi
systemctl enable --now sddm

echo "[\$(date '+%F %T')] Sunshine first boot installation complete"
FIRSTBOOT

vm_firstboot_unit "$WORK_FILE" sunshine-firstboot "$SUNSHINE_FIRSTBOOT_TMP" \
  --description "Sunshine game streaming first boot installation" \
  --cloud-init yes || exit 1
SUNSHINE_FIRSTBOOT_MARKER="$VM_FIRSTBOOT_MARKER"

vm_claim_vmid
msg_info "Creating a Debian 13 Sunshine VM"
qm create "$VMID" -agent 1${MACHINE} -tablet 0 -bios ovmf${CPU_TYPE} -cores "$CORE_COUNT" -memory "$RAM_SIZE" \
  -name "$HN" -tags community-script,sunshine -net0 "virtio,bridge=$BRG,macaddr=$MAC$VLAN$MTU" -onboot 1 -ostype l26 -scsihw virtio-scsi-pci
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

msg_ok "Created a Debian 13 Sunshine VM ${CL}${BL}(${HN})"
attach_passthrough
vm_start_vm "Sunshine VM"
vm_wait_for_ip 120 || true

display_cloud_init_info "$VMID" "$HN"

vm_print_summary \
  "GPU=${GPU_SLOT:-not assigned}" \
  "OS=${OS_LABEL}" \
  "Sunshine=${SUNSHINE_TAG}" \
  "Steam=${INSTALL_STEAM}" \
  "Dolphin=${INSTALL_DOLPHIN}" \
  "Pegasus=${INSTALL_PEGASUS}" \
  "DesktopAutologin=${DESKTOP_AUTOLOGIN}" \
  "WebUI=https://${VM_IP:-pending}:47990"
NEXT_STEPS=(
  "First boot installs the desktop and Sunshine in the VM; follow it with: journalctl -u sunshine-firstboot -f (log: /var/log/sunshine-firstboot.log)"
  "Reboot the guest once first boot completes, before testing anything that needs firmware or acceleration."
  "Log in on the GPU-connected monitor as ${CLOUDINIT_USER} (noVNC works only without GPU assignment). Dummy-only operation needs VM_DESKTOP_AUTOLOGIN=yes; Sunshine starts at graphical login."
  "Open https://<vm-ip>:47990, set Sunshine credentials, then enter the PIN displayed by Moonlight in Sunshine's PIN page."
  "For 4K60, select the GPU-connected output at 3840x2160 and 60 Hz in Plasma Display Settings if the monitor/dummy supports it; check hardware encoding in the Sunshine log."
)
if [[ "$INSTALL_PEGASUS" == "yes" ]]; then
  NEXT_STEPS+=("Pegasus Frontend is an alpha install; its game collections are user-owned.")
fi
vm_next_steps "${NEXT_STEPS[@]}"

vm_finish "VM created. Sunshine installation continues in the VM on first boot."
