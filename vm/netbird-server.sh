#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://netbird.io

COMMUNITY_SCRIPTS_URL="${COMMUNITY_SCRIPTS_URL:-https://raw.githubusercontent.com/community-scripts/DevScripts/main}"
source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/pve/vm-core.func")
load_functions

APP="NetBird Server"
APP_TYPE="vm"
NSAPP="netbird-server"
var_os="debian"
var_version="13"
GEN_MAC=02:$(openssl rand -hex 5 | awk '{print toupper($0)}' | sed 's/\(..\)/\1:/g; s/.$//')
RANDOM_UUID="$(cat /proc/sys/kernel/random/uuid)"
METHOD=""
USE_CLOUD_INIT="no"
OS_TYPE="debian"
OS_VERSION="13"
OS_CODENAME="trixie"
OS_DISPLAY="Debian 13 (Trixie)"
THIN="discard=on,ssd=1,"
NETBIRD_DOMAIN_INPUT=""
NETBIRD_PROXY_TYPE_INPUT="0"
NETBIRD_EMAIL_INPUT=""
DOCKER_PREINSTALLED="no"
DOCKER_INSTALL_MARKER=""
NETBIRD_SETUP_MARKER=""

header_info
echo -e "\n Loading..."

set -Eeo pipefail
shopt -s inherit_errexit
trap 'error_handler $LINENO "$BASH_COMMAND"' ERR
trap cleanup EXIT
trap 'post_update_to_api "failed" "130"' SIGINT
trap 'post_update_to_api "failed" "143"' SIGTERM
trap 'post_update_to_api "failed" "129"; exit 129' SIGHUP

TEMP_DIR=$(mktemp -d)
pushd "$TEMP_DIR" >/dev/null

vm_preflight
vm_require_tools virt-customize jq

function configure_netbird_setup() {
  if [[ "${VM_UNATTENDED:-0}" == "1" ]]; then
    if [[ -z "${VM_NETBIRD_DOMAIN:-}" ]]; then
      msg_error "An unattended NetBird Server install needs VM_NETBIRD_DOMAIN"
      msg_error "Set it to the public domain whose DNS A record points at this VM, e.g. VM_NETBIRD_DOMAIN=netbird.my-domain.com"
      exit 1
    fi
    NETBIRD_DOMAIN_INPUT="$VM_NETBIRD_DOMAIN"
    NETBIRD_PROXY_TYPE_INPUT="${VM_NETBIRD_PROXY_TYPE:-0}"
    NETBIRD_EMAIL_INPUT="${VM_NETBIRD_EMAIL:-admin@${NETBIRD_DOMAIN_INPUT}}"
    echo -e "${INFO}${BOLD}${DGN}NetBird Domain: ${BGN}${NETBIRD_DOMAIN_INPUT}${CL}"
    echo -e "${INFO}${BOLD}${DGN}Reverse Proxy: ${BGN}${NETBIRD_PROXY_TYPE_INPUT}${CL}"
    echo -e "${INFO}${BOLD}${DGN}Let's Encrypt Email: ${BGN}${NETBIRD_EMAIL_INPUT}${CL}"
    return
  fi

  while true; do
    if vm_dialog inputbox "NETBIRD DOMAIN" \
      "Enter the public domain for your NetBird server.\n(DNS A record must point to this VM's public IP)\n\ne.g. netbird.my-domain.com" \
      11 65 "" --cancel-button Exit-Script; then
      NETBIRD_DOMAIN_INPUT="$VM_DIALOG_RESULT"
      if [[ -z "$NETBIRD_DOMAIN_INPUT" ]] || [[ "$NETBIRD_DOMAIN_INPUT" == "netbird.example.com" ]]; then
        vm_dialog msgbox "INVALID DOMAIN" "Please enter a valid domain name." 8 50
        continue
      fi
      echo -e "${INFO}${BOLD}${DGN}NetBird Domain: ${BGN}${NETBIRD_DOMAIN_INPUT}${CL}"
      break
    else
      exit_script
    fi
  done

  if vm_dialog radiolist "REVERSE PROXY" \
    "Select the reverse proxy for NetBird" 14 70 4 \
    "0" "Traefik (recommended, built-in with auto TLS)" ON \
    "2" "Nginx (generates config template)" OFF \
    "3" "Nginx Proxy Manager" OFF \
    "5" "Other/Manual" OFF; then
    NETBIRD_PROXY_TYPE_INPUT="$VM_DIALOG_RESULT"
    echo -e "${INFO}${BOLD}${DGN}Reverse Proxy: ${BGN}${NETBIRD_PROXY_TYPE_INPUT}${CL}"
  else
    exit_script
  fi

  if [[ "$NETBIRD_PROXY_TYPE_INPUT" == "0" ]]; then
    while true; do
      if vm_dialog inputbox "LETSENCRYPT EMAIL" \
        "Enter your email for Let's Encrypt certificates:" 8 65 "" --cancel-button Exit-Script; then
        NETBIRD_EMAIL_INPUT="$VM_DIALOG_RESULT"
        if [[ -z "$NETBIRD_EMAIL_INPUT" ]]; then
          vm_dialog msgbox "INVALID EMAIL" "Email is required for Let's Encrypt." 8 50
          continue
        fi
        echo -e "${INFO}${BOLD}${DGN}Let's Encrypt Email: ${BGN}${NETBIRD_EMAIL_INPUT}${CL}"
        break
      else
        exit_script
      fi
    done
  fi
}

function select_os() {
  if [[ -n "${1:-}" ]]; then
    OS_CHOICE="$1"
  elif [[ "${VM_UNATTENDED:-0}" == "1" ]]; then
    OS_CHOICE="${VM_OS_VERSION:-debian13}"
  elif vm_dialog radiolist "SELECT OS" \
    "Choose Operating System for NetBird Server VM" 15 68 4 \
    "debian13" "Debian 13 (Trixie) - Latest" ON \
    "debian12" "Debian 12 (Bookworm) - Stable" OFF \
    "ubuntu2604" "Ubuntu 26.04 LTS (Resolute)" OFF \
    "ubuntu2404" "Ubuntu 24.04 LTS (Noble)" OFF; then
    OS_CHOICE="$VM_DIALOG_RESULT"
  else
    exit_script
  fi

  case $OS_CHOICE in
  debian13)
    OS_TYPE="debian"
    OS_VERSION="13"
    OS_CODENAME="trixie"
    OS_DISPLAY="Debian 13 (Trixie)"
    ;;
  debian12)
    OS_TYPE="debian"
    OS_VERSION="12"
    OS_CODENAME="bookworm"
    OS_DISPLAY="Debian 12 (Bookworm)"
    ;;
  ubuntu2604)
    OS_TYPE="ubuntu"
    OS_VERSION="26.04"
    OS_CODENAME="resolute"
    OS_DISPLAY="Ubuntu 26.04 LTS"
    ;;
  ubuntu2404)
    OS_TYPE="ubuntu"
    OS_VERSION="24.04"
    OS_CODENAME="noble"
    OS_DISPLAY="Ubuntu 24.04 LTS"
    ;;
  *)
    msg_error "Unsupported OS '${OS_CHOICE}' (expected debian13, debian12, ubuntu2604 or ubuntu2404)"
    exit 1
    ;;
  esac
  var_os="$OS_TYPE"
  var_version="$OS_VERSION"
  echo -e "${OS}${BOLD}${DGN}Operating System: ${BGN}${OS_DISPLAY}${CL}"
}

function select_cloud_init() {
  VM_CLOUD_INIT="${VM_CLOUD_INIT:-yes}"
  CLOUDINIT_REQUIRED=0
  if [[ "$OS_TYPE" == "ubuntu" ]]; then
    CLOUDINIT_REQUIRED=1
  fi
  vm_prompt_cloud_init "$OS_TYPE"
}

function get_image_url() {
  local arch
  arch=$(vm_arch_resolve amd64 arm64)
  case $OS_TYPE in
  debian)
    if [[ "$USE_CLOUD_INIT" == "yes" ]]; then
      echo "https://cloud.debian.org/images/cloud/${OS_CODENAME}/latest/debian-${OS_VERSION}-generic-${arch}.qcow2"
    else
      echo "https://cloud.debian.org/images/cloud/${OS_CODENAME}/latest/debian-${OS_VERSION}-nocloud-${arch}.qcow2"
    fi
    ;;
  ubuntu)
    echo "https://cloud-images.ubuntu.com/${OS_CODENAME}/current/${OS_CODENAME}-server-cloudimg-${arch}.img"
    ;;
  esac
}

function default_settings() {
  select_os "${VM_OS_VERSION:-}"
  vm_apply_machine_type "q35"
  VMID=$(get_valid_nextid)
  DISK_SIZE="10G"
  DISK_CACHE=""
  HN="netbird"
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
  select_os
  vm_prompt_vmid "${VMID:-$(get_valid_nextid)}"
  vm_prompt_machine_type "q35"
  vm_prompt_disk_size "10G"
  vm_prompt_disk_cache "none"
  vm_prompt_hostname "netbird"
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

  if vm_confirm_advanced_settings "Ready to create a NetBird Server VM?"; then
    echo -e "${CREATING}${BOLD}${DGN}Creating a NetBird Server VM using the above advanced settings${CL}"
  else
    header_info
    echo -e "${ADVANCED}${BOLD}${RD}Using Advanced Settings${CL}"
    advanced_settings
  fi
}

vm_start_script "Use Default Settings?\n\nDefaults:\n• 2 CPU Cores\n• 2 GB RAM\n• 10 GB Disk\n• Cloud-Init enabled" 14 58
select_cloud_init
configure_netbird_setup
post_to_api_vm

vm_select_storage "$HN"
vm_define_disk_references 2

msg_info "Retrieving the URL for the ${OS_DISPLAY} Disk Image"
URL=$(get_image_url)
CACHE_FILE="$(vm_image_cache_path "$URL")"
msg_ok "${CL}${BL}${URL}${CL}"

MIN_IMAGE_BYTES=$((100 * 1024 * 1024))
vm_fetch_image "$URL" "$CACHE_FILE" --cache --min-bytes "$MIN_IMAGE_BYTES" || exit 115

WORK_FILE="$TEMP_DIR/netbird.qcow2"
cp "$CACHE_FILE" "$WORK_FILE"

if [[ "${USE_CLOUD_INIT:-no}" != "yes" ]]; then
  msg_info "Expanding the root filesystem to ${DISK_SIZE}"
  vm_expand_image "$WORK_FILE" "$DISK_SIZE" || true
fi

export LIBGUESTFS_BACKEND_SETTINGS=dns=8.8.8.8,1.1.1.1

msg_info "Installing base packages"
if vm_customize "NetBird base packages" "$WORK_FILE" --install qemu-guest-agent,curl,ca-certificates,jq; then
  msg_ok "Installed base packages"

  msg_info "Installing Docker"
  if vm_customize "Docker" "$WORK_FILE" \
    --run-command 'bash -o pipefail -c "curl -fsSL https://get.docker.com | sh"' \
    --run-command 'systemctl enable docker'; then
    DOCKER_PREINSTALLED="yes"
    msg_ok "Installed Docker"

    DOCKER_DAEMON_TMP="$TEMP_DIR/docker-daemon.json"
    cat >"$DOCKER_DAEMON_TMP" <<'JSON'
{
  "storage-driver": "overlay2",
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
JSON
    vm_customize "Docker daemon" "$WORK_FILE" \
      --mkdir /etc/docker \
      --upload "${DOCKER_DAEMON_TMP}:/etc/docker/daemon.json" || msg_warn "Docker daemon tuning failed; continuing with Docker defaults"
  else
    msg_warn "Docker pre-install failed; installation is pending on first boot."
  fi
else
  msg_warn "Package pre-install failed; Docker installation is pending on first boot."
fi

NETBIRD_ENV_TMP="$TEMP_DIR/netbird.env"
cat >"$NETBIRD_ENV_TMP" <<ENVEOF
NETBIRD_NON_INTERACTIVE="true"
NETBIRD_DOMAIN="${NETBIRD_DOMAIN_INPUT}"
NETBIRD_REVERSE_PROXY_TYPE="${NETBIRD_PROXY_TYPE_INPUT}"
NETBIRD_LETSENCRYPT_EMAIL="${NETBIRD_EMAIL_INPUT}"
NETBIRD_ENABLE_PROXY="false"
NETBIRD_ENABLE_CROWDSEC="false"
NETBIRD_BIND_LOCALHOST_ONLY="false"
ENVEOF
vm_customize "NetBird configuration" "$WORK_FILE" \
  --upload "${NETBIRD_ENV_TMP}:/root/netbird.env" || exit 1

NETBIRD_SETUP_TMP="$TEMP_DIR/netbird-setup.sh"
cat >"$NETBIRD_SETUP_TMP" <<'SETUPEOF'
#!/usr/bin/env bash
set -Eeuo pipefail
exec > /var/log/netbird-setup.log 2>&1

echo "[$(date)] Starting NetBird automated setup"

for _ in {1..60}; do
  docker info >/dev/null 2>&1 && break
  sleep 5
done
docker info >/dev/null 2>&1 || {
  echo "[$(date)] ERROR: Docker not ready after 5 min"
  exit 1
}

set -a
source /root/netbird.env
set +a

curl -fsSL https://github.com/netbirdio/netbird/releases/latest/download/getting-started.sh \
  -o /root/getting-started.sh

echo "[$(date)] Running NetBird getting-started.sh"
bash /root/getting-started.sh
echo "[$(date)] NetBird setup completed"
SETUPEOF

vm_prepare_cloud_image "$WORK_FILE" "$HN" || true

if [[ "$DOCKER_PREINSTALLED" == "no" ]]; then
  DOCKER_INSTALL_TMP="$TEMP_DIR/install-docker.sh"
  cat >"$DOCKER_INSTALL_TMP" <<'DOCKEREOF'
#!/usr/bin/env bash
set -Eeuo pipefail
export DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a
exec > /var/log/install-docker.log 2>&1

echo "[$(date)] Starting Docker installation"
for _ in {1..30}; do
  ping -c 1 8.8.8.8 >/dev/null 2>&1 && break
  sleep 2
done

apt-get update
apt-get install -y qemu-guest-agent curl ca-certificates jq
bash -o pipefail -c "curl -fsSL https://get.docker.com | sh"
systemctl enable docker
install -d /etc/docker
cat > /etc/docker/daemon.json <<'JSON'
{
  "storage-driver": "overlay2",
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
JSON
systemctl start docker
echo "[$(date)] Docker installation completed"
DOCKEREOF

  vm_firstboot_unit "$WORK_FILE" install-docker "$DOCKER_INSTALL_TMP" \
    --description "Install Docker on first boot" \
    --cloud-init "$USE_CLOUD_INIT" || exit 1
  DOCKER_INSTALL_MARKER="$VM_FIRSTBOOT_MARKER"
fi

NETBIRD_AFTER=(--after docker.service)
if [[ "$DOCKER_PREINSTALLED" == "no" ]]; then
  NETBIRD_AFTER+=(--after install-docker.service)
fi
vm_firstboot_unit "$WORK_FILE" netbird-setup "$NETBIRD_SETUP_TMP" \
  --description "NetBird initial setup" \
  "${NETBIRD_AFTER[@]}" \
  --cloud-init "$USE_CLOUD_INIT" || exit 1
NETBIRD_SETUP_MARKER="$VM_FIRSTBOOT_MARKER"

vm_claim_vmid
msg_info "Creating NetBird Server VM shell"
qm create "$VMID" -agent 1${MACHINE} -tablet 0 -bios ovmf${CPU_TYPE} -cores "$CORE_COUNT" -memory "$RAM_SIZE" \
  -name "$HN" -tags community-script -net0 "virtio,bridge=$BRG,macaddr=$MAC$VLAN$MTU" -onboot 1 -ostype l26 -scsihw virtio-scsi-pci >/dev/null
vm_mark_created
msg_ok "Created VM shell"

vm_alloc_efi_disk "$DISK0"
vm_import_disk "$VMID" "$WORK_FILE" "$STORAGE"

DISK_OPTIONS="${DISK_CACHE}${THIN}"
DISK_OPTIONS="${DISK_OPTIONS%,}"
ROOT_DISK="$VM_IMPORTED_DISK"
[[ -n "$DISK_OPTIONS" ]] && ROOT_DISK="${ROOT_DISK},${DISK_OPTIONS}"

msg_info "Attaching EFI and root disk"
qm set "$VMID" \
  --efidisk0 "${DISK0_REF}${FORMAT}" \
  --scsi0 "$ROOT_DISK" \
  --boot order=scsi0 \
  --serial0 socket >/dev/null
msg_ok "Attached EFI and root disk"

vm_resize_disk "scsi0" "$DISK_SIZE"
set_description

vm_provision "$VMID"
if [[ "$USE_CLOUD_INIT" == "yes" && -n "${CLOUDINIT_SSH_KEYS:-}" ]]; then
  $STD qm set "$VMID" --sshkeys "$CLOUDINIT_SSH_KEYS"
fi

vm_start_vm "NetBird Server VM"
vm_wait_for_ip 180 || true

if [[ "$USE_CLOUD_INIT" == "yes" ]]; then
  display_cloud_init_info "$VMID" "$HN"
else
  msg_warn "Debian nocloud console login: root, no password. Set one before exposing the VM."
fi

DOCKER_STATUS="Pre-installed"
if [[ "$DOCKER_PREINSTALLED" == "no" ]]; then
  DOCKER_STATUS="First-boot unit install-docker.service${DOCKER_INSTALL_MARKER:+ (${DOCKER_INSTALL_MARKER})}"
fi

vm_print_summary \
  "OS=${OS_DISPLAY}" \
  "Domain=https://${NETBIRD_DOMAIN_INPUT}" \
  "Docker=${DOCKER_STATUS}" \
  "NetBird unit=netbird-setup.service" \
  "Setup marker=${NETBIRD_SETUP_MARKER}"
vm_next_steps \
  "NetBird installation continues in the VM on first boot." \
  "Monitor setup with: tail -f /var/log/netbird-setup.log (Docker install: /var/log/install-docker.log)" \
  "Keep ports open: 80/tcp, 443/tcp, 3478/udp."
vm_finish "VM created. NetBird installation continues in the VM on first boot."
