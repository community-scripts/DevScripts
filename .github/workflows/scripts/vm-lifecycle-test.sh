#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd)"
CORE="${CORE:-$ROOT/.core/pve/vm-core.func}"
[[ -r "$CORE" ]] || {
  echo "Missing Core checkout: $CORE" >&2
  exit 1
}
TEST_DIR="$(mktemp -d)"
trap 'rm -rf -- "$TEST_DIR"' EXIT
MOCK="$TEST_DIR/host-mocks.sh"

cat >"$MOCK" <<'MOCKEOF'
_cs_source_func() { source "$CORE_DIR/$1"; }
pveversion() { :; }
load_functions() { color; formatting; icons; default_vars; STD=""; }
vm_preflight() { :; }
header_info() { :; }
post_to_api_vm() { echo "api created" >>"$EVENTS"; }
post_update_to_api() { echo "api $*" >>"$EVENTS"; }
get_valid_nextid() { echo 100; }
msg_info() { echo "INFO $*"; }
msg_ok() { echo "OK $*"; }
msg_warn() { echo "WARN $*"; }
msg_error() { echo "ERROR $*" >&2; }
sleep() { :; }
clear() { :; }
hostname() { echo proxmox; }
timeout() { shift; "$@"; }
cat() {
  if [[ "$*" == /proc/sys/kernel/random/uuid ]]; then
    echo "00000000-0000-4000-8000-000000000001"
  else
    command cat "$@"
  fi
}
grep() {
  case "$*" in
  "MemTotal /proc/meminfo") echo "MemTotal: 16777216 kB" ;;
  "SwapTotal /proc/meminfo") echo "SwapTotal: 0 kB" ;;
  *) command grep "$@" ;;
  esac
}
ufw() { echo "Status: inactive"; }
mktemp() {
  if [[ "$*" == *-d* ]]; then
    command mktemp -d "$CASE_DIR/work.XXXXXX"
  else
    command mktemp "$CASE_DIR/file.XXXXXX"
  fi
}
df() {
  echo "Filesystem 1K-blocks Used Available Use% Mounted"
  if [[ "$*" == *-BG* ]]; then
    echo "/dev/mock 100G 10G 90G 10% /"
  else
    echo "/dev/mock 104857600 10485760 94371840 10% /"
  fi
}
ip() { printf '1: vmbr0: <UP>\n2: vmbr1: <UP>\n'; }
whiptail() { echo "Unexpected interactive dialog: $*" >&2; return 2; }
vm_prompt_cloud_init() {
  USE_CLOUD_INIT=yes CLOUDINIT_USER="${CLOUDINIT_USER:-$1}" CLOUDINIT_PASSWORD=test-password
  CLOUDINIT_NETWORK_MODE=dhcp
  if [[ "$FAILURE" == ssh ]]; then
    CLOUDINIT_SSH_KEYS="$CASE_DIR/keys.pub"
    echo "test-only" >"$CLOUDINIT_SSH_KEYS"
  fi
}
load_cloud_init_functions() { :; }
vm_require_tools() { echo "tools $*" >>"$EVENTS"; }
vm_wait_http() { echo "http $*" >>"$EVENTS"; }
# Fixture releases. The asset regex a script passes must match the fixture's
# file name, so a pattern that would match nothing upstream fails here too.
vm_release_asset() {
  local tag asset
  echo "release $*" >>"$EVENTS"
  case "$2" in
  IceWhaleTech/ZimaOS) tag="1.8.0-beta2" asset="zimaos-x86_64-1.8.0-beta2_installer.iso" ;;
  home-assistant/operating-system) tag="${4:-16.0}" asset="haos_generic-aarch64-${4:-16.0}.qcow2.xz" ;;
  derailed/k9s) tag="v0.50.0" asset="k9s_Linux_amd64.tar.gz" ;;
  moonlight-stream/moonlight-qt) tag="v6.2.0" asset="Moonlight-6.2.0-x86_64.AppImage" ;;
  *) echo "Unexpected release repository: $2" >&2; return 2 ;;
  esac
  [[ "$asset" =~ $3 ]] || { echo "Release pattern $3 does not match $asset" >&2; return 2; }
  VM_RELEASE_TAG="$tag" VM_RELEASE_VERSION="${tag#v}" VM_RELEASE_ASSET="$asset"
  VM_RELEASE_URL="https://example.invalid/$asset" VM_RELEASE_SHA256=""
  case "$2" in
  moonlight-stream/moonlight-qt)
    VM_RELEASE_SHA256="$(printf 'a%.0s' {1..64})"
    ;;
  esac
  [[ "$FAILURE" != digest ]] || VM_RELEASE_SHA256=""
  return 0
}
setup_cloud_init() {
  echo "provision $*" >>"$EVENTS"
  CLOUDINIT_CRED_FILE="$CASE_DIR/credentials"
  echo "test-only generated password" >"$CLOUDINIT_CRED_FILE"
}
display_cloud_init_info() { echo "credentials $*" >>"$EVENTS"; }
# Without the VM's MAC the lookup answers with a container bridge address, the
# way the real guest agent lists docker0 first; scripts must pass $MAC.
get_vm_ip() {
  echo "ip-lookup $*" >>"$EVENTS"
  if [[ -z "${3:-}" ]]; then
    echo "10.88.0.1"
  elif [[ "${3,,}" == "${MAC,,}" ]]; then
    echo "192.0.2.42"
  else
    return 1
  fi
}
vm_select_storage() {
  STORAGE=disk-store
  vm_apply_storage_layout "$STORAGE_KIND"
}
vm_select_iso_storage() {
  ISO_STORAGE=iso-store ISO_VOLUME="iso-store:iso/$1" ISO_PATH="$CASE_DIR/$1"
  if [[ "$FAILURE" == cache ]]; then ISO_PATH="$(vm_image_cache_path "$1")"; fi
  echo "iso $ISO_VOLUME" >>"$EVENTS"
}
vm_image_cache_path() {
  if [[ "$FAILURE" == cache ]]; then (exit 7); fi
  echo "$CASE_DIR/cache-$(basename "$1")"
}
vm_fetch_image() {
  if [[ "$FAILURE" == download && "$1" == https://example.invalid/* ]]; then return 7; fi
  if [[ "$FAILURE" == bashitdownload && "$1" == *Bash-it/bash-it/archive/* ]]; then return 7; fi
  printf 'mock-image' >"$2"
  echo "fetch $1" >>"$EVENTS"
}
vm_extract_image() {
  local target="${2:-$CASE_DIR/extracted-$(basename "${1%.*}")}"
  printf 'mock-image' >"$target"
  VM_IMAGE_FILE="$target"
}
vm_prepare_cloud_image() { echo "prepare $*" >>"$EVENTS"; }
vm_expand_image() { echo "expand $*" >>"$EVENTS"; }
vm_resize_disk() { echo "resize ${DISK_SIZE}" >>"$EVENTS"; }
vm_alloc_efi_disk() { echo "efi $*" >>"$EVENTS"; }
set_description() {
  echo "description" >>"$EVENTS"
  [[ "$FAILURE" != description ]] || return 7
}
virt-customize() {
  echo "customize $*" >>"$EVENTS"
  local argument previous="" upload
  for argument in "$@"; do
    if [[ "$previous" == --upload && "$argument" == *:/usr/local/sbin/* ]]; then
      upload="${argument%%:*}"
      bash -n "$upload" || return 1
      cp "$upload" "$CASE_DIR/firstboot.sh"
    fi
    if [[ "$previous" == --upload && "$argument" == *:/etc/systemd/system/*.service ]]; then
      upload="${argument%%:*}"
      if grep -q 'After=.*cloud-final.service' "$upload"; then
        echo "firstboot-after-cloud-final" >>"$EVENTS"
      fi
    fi
    previous="$argument"
  done
  [[ "$FAILURE" != customize ]] || return 7
}
qemu-img() { echo "image $*" >>"$EVENTS"; }
gunzip() { printf 'mock-image'; }
pvesh() { return 1; }
pvesm() {
  case "$1" in
  status) printf 'Name Type Status Total Used Available %%\ndisk-store %s active 100 10 90 10\n' "$STORAGE_KIND" ;;
  alloc | free) echo "storage $*" >>"$EVENTS" ;;
  list) echo "disk-store:vm-100-disk-0 raw images 1 100" ;;
  *) echo "Unexpected pvesm: $*" >&2; return 2 ;;
  esac
}
qm() {
  echo "qm $*" >>"$EVENTS"
  case "$1" in
  create) echo stopped >"$CASE_DIR/state" ;;
  start)
    [[ "$FAILURE" != start ]] || return 7
    echo running >"$CASE_DIR/state"
    ;;
  shutdown) echo stopped >"$CASE_DIR/state" ;;
  status)
    [[ -f "$CASE_DIR/state" ]] || return 1
    echo "status: $(cat "$CASE_DIR/state")"
    ;;
  sendkey) if [[ "$SCRIPT_SLUG:$3" == openwrt-vm:ret ]]; then echo stopped >"$CASE_DIR/state"; fi ;;
  importdisk | disk)
    [[ "$*" != *--help* ]] || return 0
    [[ "$FAILURE" != import ]] || return 7
    local index=0 prefix="" extension="" ref
    if grep -Eq '^efi |^storage alloc ' "$EVENTS"; then index=1; fi
    case "$STORAGE_KIND" in
    dir) prefix="100/" extension=".qcow2" ;;
    btrfs) prefix="100/" extension=".raw" ;;
    esac
    ref="disk-store:${prefix}vm-100-disk-${index}${extension}"
    echo "imported $ref" >>"$EVENTS"
    echo "successfully imported disk '$ref'"
    ;;
  set) [[ "$FAILURE:$*" != ssh:*--sshkeys* ]] || return 7 ;;
  guest)
    if [[ "$SCRIPT_SLUG" == netbird-server ]]; then
      printf '[{"name":"docker0","hardware-address":"02:00:00:00:00:99","ip-addresses":[{"ip-address-type":"ipv4","ip-address":"10.88.0.1"}]},{"name":"ens18","hardware-address":"%s","ip-addresses":[{"ip-address-type":"ipv4","ip-address":"192.0.2.42"}]}]\n' "$MAC"
    else
      return 1
    fi
    ;;
  config) echo "unused0: disk-store:vm-100-disk-0" ;;
  destroy | stop) : ;;
  *) echo "Unexpected qm: $*" >&2; return 2 ;;
  esac
}
curl() {
  local url="" output="" arg previous="" payload=""
  for arg in "$@"; do
    [[ "$previous" != -o ]] || output="$arg"
    [[ "$arg" != https:* && "$arg" != http:* ]] || url="$arg"
    previous="$arg"
  done
  case "$url" in
  https://github.com/Bash-it/bash-it/releases/latest)
    [[ "$FAILURE" != bashit ]] || return 7
    payload='/Bash-it/bash-it/releases/tag/v3.2.0' ;;
  */pve/vm-core.func)
    cat "$CORE"
    printf '\nsource %q\n' "$MOCK"
    return
    ;;
  */home-assistant/version/*) payload='{"ova":"16.0","hassos":{"generic-aarch64":"16.0"}}' ;;
  *blissos-x86*) payload='Bliss-v16.9.7-x86_64-OFFICIAL-foss-20261001.iso' ;;
  *cachyos-arch*) payload='desktop/261001/' ;;
  *api.umbrel.com*) payload='{"version":"1.7.4"}' ;;
  *IceWhaleTech/ZimaOS*) payload='{"tag_name": "1.8.0-beta2", "assets":[{"browser_download_url": "https://example.invalid/zimaos-x86_64-1.8.0-beta2_installer.iso"}]}' ;;
  https://openwrt.org) payload='Current stable release - OpenWrt 25.12.0' ;;
  https://download.freebsd.org/releases/VM-IMAGES/) payload='15.0-RELEASE' ;;
  *FreeBSD-*.qcow2.xz | *downloads.openwrt.org/releases/*) payload='mock-download' ;;
  *fw-update.ui.com*) payload='{"_embedded":{"firmware":[{"product":"unifi-os-server","platform":"linux-x64","version":"5.1.42","version_major":5,"version_minor":1,"version_patch":42,"_links":{"data":{"href":"https://example.invalid/unifi.bin"}}}]}}' ;;
  https://example.invalid/* | *k9s_Linux_*) payload='mock-download' ;;
  *) echo "Unexpected URL: $url" >&2; return 2 ;;
  esac
  if [[ -n "$output" ]]; then
    printf '%s\n' "$payload" >"$output"
  else
    printf '%s\n' "$payload"
  fi
}
MOCKEOF

export CORE MOCK
CORE_DIR="$(cd -- "$(dirname -- "$CORE")/.." && pwd)"
export CORE_DIR
fail() {
  echo "FAIL: $*" >&2
  cat "$CASE_DIR/output" >&2
  exit 1
}
checked=0
failures_checked=0
runs_checked=0
for script in "$ROOT"/vm/*.sh; do
  slug="$(basename "$script" .sh)"
  # ONLY="netbird-server waydroid-vm" limits a local run to those scripts.
  if [[ -n "${ONLY:-}" && " ${ONLY} " != *" ${slug} "* ]]; then continue; fi
  SCRIPT_SLUG="$slug"
  export SCRIPT_SLUG
  arch=amd64
  [[ "$slug" != pimox-haos-vm ]] || arch=arm64
  for start in yes no; do
    for kind in dir lvmthin btrfs; do
      CASE_DIR="$TEST_DIR/$slug-$start-$kind"
      mkdir "$CASE_DIR"
      EVENTS="$CASE_DIR/events"
      export CASE_DIR EVENTS
      rc=0
      BASH_ENV="$MOCK" VM_UNATTENDED=1 VM_START="$start" VM_NETBIRD_DOMAIN=netbird.example.invalid \
        VM_ARCH="$arch" STORAGE_KIND="$kind" FAILURE=none \
        bash "$script" >"$CASE_DIR/output" 2>&1 || rc=$?
      [[ "$rc" == 0 ]] || fail "$slug $start $kind exited $rc"
      ! grep -Eq '^\[ERROR\]|^ERROR ' "$CASE_DIR/output" || fail "$slug reported errors despite success"
      grep -q '^api done none$' "$EVENTS" || fail "$slug never reported completion"
      case "$slug" in
      blissos-vm | cachyos-vm | nextcloud-vm | owncloud-vm | umbrel-os-vm | zimaos-vm)
        grep -q -- '-cdrom iso-store:iso/' "$EVENTS" || fail "$slug ISO storage not attached"
        ! grep -q 'qm importdisk' "$EVENTS" || fail "$slug imported an ISO as disk"
        ;;
      *)
        grep -Eq '^qm (importdisk |disk import [0-9])' "$EVENTS" || fail "$slug did not import its image"
        imported_ref="$(sed -n 's/^imported //p' "$EVENTS")"
        grep -E '^qm set .*--?scsi0 ' "$EVENTS" | grep -Fq "$imported_ref" || fail "$slug attached the wrong imported disk"
        ;;
      esac
      case "$slug:$start" in
      openwrt-vm:no | opnsense-vm:no)
        [[ "$(cat "$CASE_DIR/state")" == stopped ]] || fail "$slug ignored START_VM=no"
        ;;
      *:no)
        ! grep -q '^qm start ' "$EVENTS" || fail "$slug started despite START_VM=no"
        ;;
      *:yes)
        grep -q '^qm start ' "$EVENTS" || fail "$slug did not start"
        [[ "$(cat "$CASE_DIR/state")" == running ]] || fail "$slug did not finish running"
        ;;
      esac
      if [[ "$slug" == k3s-vm ]]; then
        last_custom="$(grep -n '^customize ' "$EVENTS" | tail -1 | cut -d: -f1)"
        imported="$(grep -nE '^qm (importdisk|disk import) [0-9]' "$EVENTS" | cut -d: -f1)"
        ((last_custom < imported)) || fail "K3s customized after import"
      fi
      case "$slug" in
      moonlight-vm)
        [[ -s "$CASE_DIR/firstboot.sh" ]] || fail "$slug did not stage a parseable first-boot installer"
        grep -q '^firstboot-after-cloud-final$' "$EVENTS" || fail "$slug first boot is not ordered after Cloud-Init"
        ! grep -Eq 'qm set .*--(hostpci|usb)[0-9]' "$EVENTS" || fail "$slug assigned devices without an explicit selection"
        ;;
      esac
      ! grep -q '10\.88\.0\.1' "$CASE_DIR/output" || fail "$slug reported a container bridge address as the VM IP"
      if awk '$1 == "ip-lookup" && NF < 4' "$EVENTS" | grep -q .; then
        fail "$slug looked up the IP without the VM's MAC"
      fi
      if [[ "$slug:$start" == netbird-server:yes ]]; then
        grep -q '192\.0\.2\.42' "$CASE_DIR/output" || fail "NetBird did not report the VM NIC address"
      fi
      runs_checked=$((runs_checked + 1))
      echo "PASS $slug start=$start storage=$kind"
    done
  done
  failures=(description start cache)
  case "$slug" in
  k3s-vm | netbird-server | ubuntu-vm | unifi-os-server-vm | waydroid-vm | moonlight-vm) failures+=(ssh) ;;
  esac
  case "$slug" in
  blissos-vm | cachyos-vm | nextcloud-vm | owncloud-vm | umbrel-os-vm | zimaos-vm) ;;
  *) failures+=(import) ;;
  esac
  for failure in "${failures[@]}"; do
    CASE_DIR="$TEST_DIR/$slug-failure-$failure"
    mkdir "$CASE_DIR"
    EVENTS="$CASE_DIR/events"
    export CASE_DIR EVENTS
    rc=0
    BASH_ENV="$MOCK" VM_UNATTENDED=1 VM_START=yes VM_NETBIRD_DOMAIN=netbird.example.invalid \
      VM_ARCH="$arch" STORAGE_KIND=dir FAILURE="$failure" \
      bash "$script" >"$CASE_DIR/output" 2>&1 || rc=$?
    # vm_import_disk turns qm's status into its own 1; every other step keeps
    # the failing command's status.
    expected_rc=7
    [[ "$failure" != import ]] || expected_rc=1
    [[ "$rc" == "$expected_rc" ]] || fail "$slug $failure returned $rc, expected $expected_rc"
    if [[ "$failure" == cache ]]; then
      ! grep -q '^qm create ' "$EVENTS" || fail "$slug continued after a failed command substitution"
    elif [[ "$slug:$failure" != unifi-os-server-vm:import ]]; then
      ! grep -q '^qm destroy ' "$EVENTS" || fail "$slug destroyed a created VM"
      grep -q 'left in place' "$CASE_DIR/output" || fail "$slug missed preservation warning"
    fi
    ! grep -q '^api done ' "$EVENTS" || fail "$slug reported success after failure"
    echo "PASS $slug $failure failure does not report success"
    failures_checked=$((failures_checked + 1))
  done
  case "$slug" in
  moonlight-vm)
    for invalid in gpu machine user digest download customize bashit bashitdownload resetguard; do
      CASE_DIR="$TEST_DIR/$slug-invalid-$invalid"
      mkdir "$CASE_DIR"
      EVENTS="$CASE_DIR/events"
      export CASE_DIR EVENTS
      overrides=()
      case "$invalid" in
      gpu) overrides=(VM_GPU_PCI=not-a-pci-address) ;;
      machine) overrides=(VM_MACHINE=i440fx) ;;
      user) overrides=(CLOUDINIT_USER=root) ;;
      digest) overrides=(FAILURE=digest) ;;
      download) overrides=(FAILURE=download) ;;
      customize) overrides=(FAILURE=customize) ;;
      bashit | bashitdownload) overrides=(FAILURE="$invalid") ;;
      resetguard) overrides=(VM_RAVEN_RESET_GUARD=yes) ;;
      esac
      rc=0
      env BASH_ENV="$MOCK" VM_UNATTENDED=1 VM_START=no VM_ARCH=amd64 \
        STORAGE_KIND=dir FAILURE=none "${overrides[@]}" \
        bash "$script" >"$CASE_DIR/output" 2>&1 || rc=$?
      [[ "$rc" != 0 ]] || fail "$slug accepted invalid $invalid"
      ! grep -q '^qm create ' "$EVENTS" || fail "$slug created a VM despite invalid $invalid"
      ! grep -q '^api done ' "$EVENTS" || fail "$slug reported completion despite invalid $invalid"
      failures_checked=$((failures_checked + 1))
      echo "PASS $slug rejects invalid $invalid before creation"
    done
    ;;
  esac
  checked=$((checked + 1))
done
echo "All $checked VM scripts: $runs_checked complete mocked runs and $failures_checked failure cases passed."
