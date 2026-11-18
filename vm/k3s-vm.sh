#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE

COMMUNITY_SCRIPTS_URL="${COMMUNITY_SCRIPTS_URL:-https://raw.githubusercontent.com/community-scripts/DevScripts/main}"
source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/pve/vm-core.func")
load_functions

APP="K3s"
APP_TYPE="vm"
NSAPP="k3s-vm"
var_os="debian"
var_version="13"
GEN_MAC=02:$(openssl rand -hex 5 | awk '{print toupper($0)}' | sed 's/\(..\)/\1:/g; s/.$//')
RANDOM_UUID="$(cat /proc/sys/kernel/random/uuid)"
METHOD=""
INSTALL_ARGOCD_BOOTSTRAP="${INSTALL_ARGOCD_BOOTSTRAP:-1}"
USE_CLOUD_INIT="no"
OS_TYPE="debian"
OS_VERSION="13"
OS_CODENAME="trixie"
OS_DISPLAY="Debian 13 (Trixie)"
ARGOCD_BOOTSTRAP_MARKER=""
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

TEMP_DIR=$(mktemp -d)
pushd "$TEMP_DIR" >/dev/null

vm_preflight
vm_require_tools virt-customize jq

function select_os() {
  if [[ -n "${1:-}" ]]; then
    OS_CHOICE="$1"
  elif [[ "${VM_UNATTENDED:-0}" == "1" ]]; then
    OS_CHOICE="${VM_OS_VERSION:-debian13}"
  elif vm_dialog radiolist "SELECT OS" \
    "Choose Operating System for K3s VM" 15 68 5 \
    "debian13" "Debian 13 (Trixie) - Latest" ON \
    "debian12" "Debian 12 (Bookworm) - Stable" OFF \
    "ubuntu2604" "Ubuntu 26.04 LTS (Resolute)" OFF \
    "ubuntu2404" "Ubuntu 24.04 LTS (Noble)" OFF \
    "ubuntu2204" "Ubuntu 22.04 LTS (Jammy)" OFF; then
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
  ubuntu2204)
    OS_TYPE="ubuntu"
    OS_VERSION="22.04"
    OS_CODENAME="jammy"
    OS_DISPLAY="Ubuntu 22.04 LTS"
    ;;
  *)
    msg_error "Unsupported OS '${OS_CHOICE}' (expected debian13, debian12, ubuntu2604, ubuntu2404 or ubuntu2204)"
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
  HN="k3s"
  CPU_TYPE=" -cpu host"
  CORE_COUNT="2"
  RAM_SIZE="4096"
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
  vm_prompt_hostname "k3s"
  vm_prompt_cpu_model "host"
  vm_prompt_cpu_cores "2"
  vm_prompt_ram "4096"
  vm_prompt_bridge "vmbr0"
  vm_prompt_mac "$GEN_MAC"
  vm_prompt_vlan
  vm_prompt_mtu
  vm_prompt_keyboard
  vm_prompt_verbose "no"
  vm_prompt_start_vm "yes"

  if vm_confirm_advanced_settings "Ready to create a K3s VM?"; then
    echo -e "${CREATING}${BOLD}${DGN}Creating a K3s VM using the above advanced settings${CL}"
  else
    header_info
    echo -e "${ADVANCED}${BOLD}${RD}Using Advanced Settings${CL}"
    advanced_settings
  fi
}

vm_start_script "Use Default Settings?\n\nDefaults:\n• 2 CPU Cores\n• 4 GB RAM\n• 10 GB Disk\n• Cloud-Init enabled" 14 58
select_cloud_init
post_to_api_vm

vm_select_storage "$HN"
vm_define_disk_references 2

msg_info "Retrieving the URL for the ${OS_DISPLAY} image"
URL=$(get_image_url)
msg_ok "${CL}${BL}${URL}${CL}"
CACHE_FILE="$(vm_image_cache_path "$URL")"
vm_fetch_image "$URL" "$CACHE_FILE" --cache --min-bytes $((100 * 1024 * 1024)) || exit 115

WORK_FILE="$TEMP_DIR/k3s.qcow2"
cp -f "$CACHE_FILE" "$WORK_FILE"

if [[ "${USE_CLOUD_INIT:-no}" != "yes" ]]; then
  msg_info "Expanding the root filesystem to ${DISK_SIZE}"
  vm_expand_image "$WORK_FILE" "$DISK_SIZE" || true
fi

TOOL_ARCH="$(vm_arch_resolve amd64 arm64)"
msg_info "Adding K3s and Helm to image"
vm_customize "K3s and Helm" "$WORK_FILE" \
  --hostname "$HN" \
  --install curl,tar,ca-certificates,gnupg,iptables \
  --run-command 'bash -o pipefail -c "curl -sfL https://get.k3s.io | sh -s - --write-kubeconfig-mode 644"' \
  --run-command 'ln -sf /usr/local/bin/k3s /usr/local/bin/kubectl' \
  --run-command "bash -euo pipefail -c 'curl -fsSL https://get.helm.sh/helm-v3.18.1-linux-${TOOL_ARCH}.tar.gz -o /tmp/helm.tar.gz; tar -xzf /tmp/helm.tar.gz -C /tmp; install -m 0755 /tmp/linux-${TOOL_ARCH}/helm /usr/local/bin/helm; rm -rf /tmp/helm.tar.gz /tmp/linux-${TOOL_ARCH}'" \
  --run-command 'grep -qxF "export KUBECONFIG=/etc/rancher/k3s/k3s.yaml" /root/.bashrc || echo "export KUBECONFIG=/etc/rancher/k3s/k3s.yaml" >> /root/.bashrc' || exit 1
msg_ok "Added K3s and Helm to image"

msg_info "Resolving k9s release"
K9S_PATTERN="^k9s_Linux_${TOOL_ARCH}\\.tar\\.gz$"
if vm_release_asset github derailed/k9s "$K9S_PATTERN"; then
  K9S_ARCHIVE="$TEMP_DIR/$VM_RELEASE_ASSET"
  K9S_FETCH_ARGS=()
  [[ -n "$VM_RELEASE_SHA256" ]] && K9S_FETCH_ARGS=(--sha256 "$VM_RELEASE_SHA256")
  if vm_fetch_image "$VM_RELEASE_URL" "$K9S_ARCHIVE" "${K9S_FETCH_ARGS[@]}" &&
    vm_customize "k9s" "$WORK_FILE" \
      --upload "$K9S_ARCHIVE:/tmp/k9s.tar.gz" \
      --run-command 'tar -xzf /tmp/k9s.tar.gz -C /usr/local/bin k9s' \
      --run-command 'chmod +x /usr/local/bin/k9s' \
      --run-command 'rm -f /tmp/k9s.tar.gz'; then
    msg_ok "Added k9s to image"
  else
    msg_warn "Could not add k9s to image. VM creation continues without k9s."
  fi
else
  msg_warn "Could not resolve k9s release. VM creation continues without k9s."
fi

vm_prepare_cloud_image "$WORK_FILE" "$HN" || true

if [[ "$INSTALL_ARGOCD_BOOTSTRAP" == "1" ]]; then
  ARGOCD_BOOTSTRAP_TMP="$TEMP_DIR/argocd-bootstrap.sh"
  cat >"$ARGOCD_BOOTSTRAP_TMP" <<'ARGOEOF'
#!/usr/bin/env bash
set -Eeuo pipefail

export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

for _ in {1..120}; do
  if kubectl get nodes --no-headers 2>/dev/null | grep -q " Ready "; then
    break
  fi
  sleep 2
done

if ! kubectl get nodes --no-headers 2>/dev/null | grep -q " Ready "; then
  echo "K3s is not ready yet"
  exit 1
fi

kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl -n argocd rollout status deploy/argocd-server --timeout=10m
ARGOEOF

  vm_firstboot_unit "$WORK_FILE" argocd-bootstrap "$ARGOCD_BOOTSTRAP_TMP" \
    --description "ArgoCD bootstrap" \
    --after k3s.service \
    --cloud-init "$USE_CLOUD_INIT" || exit 1
  ARGOCD_BOOTSTRAP_MARKER="$VM_FIRSTBOOT_MARKER"
else
  msg_info "Skipping ArgoCD Bootstrap (INSTALL_ARGOCD_BOOTSTRAP=$INSTALL_ARGOCD_BOOTSTRAP)"
fi

vm_claim_vmid
msg_info "Creating a ${OS_DISPLAY} VM"
qm create "$VMID" -agent 1${MACHINE} -tablet 0 -bios ovmf${CPU_TYPE} -cores "$CORE_COUNT" -memory "$RAM_SIZE" \
  -name "$HN" -tags community-script -net0 "virtio,bridge=$BRG,macaddr=$MAC$VLAN$MTU" -onboot 1 -ostype l26 -scsihw virtio-scsi-pci
vm_mark_created
msg_ok "Created a K3s VM ${CL}${BL}(${HN})"

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
if [[ "$USE_CLOUD_INIT" == "yes" && -n "${CLOUDINIT_SSH_KEYS:-}" ]]; then
  $STD qm set "$VMID" --sshkeys "$CLOUDINIT_SSH_KEYS"
fi

vm_start_vm "K3s VM"
vm_wait_for_ip 120 || true

if [[ "$USE_CLOUD_INIT" == "yes" ]]; then
  display_cloud_init_info "$VMID" "$HN"
else
  msg_warn "Debian nocloud console login: root, no password. Set a password before exposing the VM."
fi

ARGO_STATUS="Disabled"
if [[ "$INSTALL_ARGOCD_BOOTSTRAP" == "1" ]]; then
  ARGO_STATUS="First-boot unit argocd-bootstrap.service${ARGOCD_BOOTSTRAP_MARKER:+ (${ARGOCD_BOOTSTRAP_MARKER})}"
fi

vm_print_summary \
  "OS=${OS_DISPLAY}" \
  "Kubeconfig=/etc/rancher/k3s/k3s.yaml" \
  "ArgoCD=${ARGO_STATUS}"
vm_next_steps \
  "K3s starts on first boot; check it with: systemctl status k3s" \
  "Use kubectl with: export KUBECONFIG=/etc/rancher/k3s/k3s.yaml" \
  "If enabled, monitor ArgoCD bootstrap with: journalctl -u argocd-bootstrap -f"
FINISH_MESSAGE="VM created. K3s starts on first boot."
if [[ "$INSTALL_ARGOCD_BOOTSTRAP" == "1" ]]; then
  FINISH_MESSAGE="VM created. K3s starts on first boot and ArgoCD bootstrap continues in the VM."
fi
vm_finish "$FINISH_MESSAGE"
