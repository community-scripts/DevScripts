#!/usr/bin/env bash
_CS_DEFAULT_URL="https://raw.githubusercontent.com/community-scripts/DevScripts/main"
_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../core}/core/build.func"
source "$_cs_boot" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/build.func")
# Copyright (c) 2021-2026 community-scripts ORG
# Author: Gentleman-Programming
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://github.com/Gentleman-Programming/gentle-shell

APP="gentle-shell"
var_tags="${var_tags:-development;ai;coding-agent}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-10}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"
var_testurl="${var_testurl:-https://github.com/community-scripts/DevScripts/issues/NEW}"

var_hostname="${var_hostname:-}"
var_projects_mode="${var_projects_mode:-}"
var_projects_path="${var_projects_path:-}"
var_projects_storage="${var_projects_storage:-}"
var_projects_size="${var_projects_size:-}"
var_gh_token="${var_gh_token:-}"

header_info "$APP"
variables
color
catch_errors

if [[ -z "${var_hostname}" ]]; then
  read -rp "  Machine name for Herdr (default: gentle-shell): " -t 60 var_hostname || var_hostname=""
fi
var_hostname="${var_hostname:-gentle-shell}"

if [[ -z "${var_projects_mode}" ]]; then
  read -rp "  Store projects [1] inside the LXC disk or [2] on existing storage (default: 1): " -t 60 var_projects_mode || var_projects_mode="1"
fi
case "${var_projects_mode}" in
  2 | external | bind | select) var_projects_mode="select" ;;
  *) var_projects_mode="internal" ;;
esac

if [[ "${var_projects_mode}" == "select" ]]; then
  if [[ -n "${var_projects_path}" ]]; then
    var_projects_mode="bind"
  elif [[ -n "${var_projects_storage}" ]]; then
    var_projects_mode="external"
  else
    mapfile -t _proj_mounts < <(
      findmnt -rno TARGET,FSTYPE 2>/dev/null |
        awk '$2 == "ext4" || $2 == "xfs" || $2 == "btrfs" {print $1}' |
        grep -Ev '^/($|boot|dev|etc|proc|root|run|sys|tmp|usr|var)'
    )
    mapfile -t _proj_storages < <(pvesm status -content rootdir 2>/dev/null | awk 'NR > 1 {print $1}')
    _proj_options=()
    echo -e "${INFO}${YW}Available storage for projects:${CL}"
    for _proj_entry in "${_proj_mounts[@]}"; do
      [[ -n "${_proj_entry}" ]] || continue
      _proj_options+=("bind:${_proj_entry}")
      echo -e "  ${BGN}[${#_proj_options[@]}]${CL} ${_proj_entry} ${YW}(existing host directory)${CL}"
    done
    for _proj_entry in "${_proj_storages[@]}"; do
      [[ -n "${_proj_entry}" ]] || continue
      _proj_options+=("storage:${_proj_entry}")
      echo -e "  ${BGN}[${#_proj_options[@]}]${CL} ${_proj_entry} ${YW}(new Proxmox volume)${CL}"
    done
    if (( ${#_proj_options[@]} == 0 )); then
      echo -e "${INFO}${YW}No storage found; projects stay on the LXC disk.${CL}"
      var_projects_mode="internal"
    else
      read -rp "  Select storage [1-${#_proj_options[@]}] (default: 1): " -t 60 _proj_choice || _proj_choice=""
      _proj_choice="${_proj_choice:-1}"
      if ! [[ "${_proj_choice}" =~ ^[0-9]+$ ]] || (( _proj_choice < 1 || _proj_choice > ${#_proj_options[@]} )); then
        msg_error "Invalid storage selection '${_proj_choice}'!"
        exit 1
      fi
      _proj_entry="${_proj_options[$((_proj_choice - 1))]}"
      if [[ "${_proj_entry}" == bind:* ]]; then
        var_projects_mode="bind"
        var_projects_path="${_proj_entry#bind:}"
        read -rp "  Subdirectory inside ${var_projects_path} (empty to use it directly): " -t 60 _proj_sub || _proj_sub=""
        _proj_sub="${_proj_sub#/}"
        _proj_sub="${_proj_sub%/}"
        if [[ -n "${_proj_sub}" ]]; then
          IFS='/' read -ra _proj_parts <<<"${_proj_sub}"
          for _proj_part in "${_proj_parts[@]}"; do
            if [[ -z "${_proj_part}" || "${_proj_part}" == "." || "${_proj_part}" == ".." ]]; then
              msg_error "Invalid subdirectory name '${_proj_sub}'!"
              exit 1
            fi
          done
          var_projects_path="${var_projects_path%/}/${_proj_sub}"
        fi
      else
        var_projects_mode="external"
        var_projects_storage="${_proj_entry#storage:}"
      fi
    fi
  fi
fi

if [[ "${var_projects_mode}" == "external" ]]; then
  var_projects_storage="${var_projects_storage:-local-lvm}"
  if ! pvesm status -content rootdir 2>/dev/null | awk 'NR>1 {print $1}' | grep -qx "${var_projects_storage}"; then
    msg_error "Storage '${var_projects_storage}' does not exist or cannot hold container mountpoints!"
    exit 1
  fi
  if [[ -z "${var_projects_size}" ]]; then
    read -rp "  Projects volume size in GB (default: 10): " -t 60 var_projects_size || var_projects_size=""
  fi
  var_projects_size="${var_projects_size:-10}"
fi

if [[ "${var_projects_mode}" == "bind" ]]; then
  case "${var_projects_path}" in
    / | /boot | /boot/* | /dev | /dev/* | /etc | /etc/* | /proc | /proc/* | /root | /root/* | /run | /run/* | /sys | /sys/* | /tmp | /tmp/* | /usr | /usr/* | /var | /var/*)
      msg_error "'${var_projects_path}' is a host system path and cannot hold projects!"
      exit 1
      ;;
  esac
  if [[ "${var_projects_path}" == *,* ]]; then
    msg_error "Directory paths containing commas are not supported by Proxmox mountpoints!"
    exit 1
  fi
  if [[ ! -d "${var_projects_path}" && -d "$(dirname "${var_projects_path}")" ]]; then
    mkdir -p "${var_projects_path}"
  fi
  if [[ ! -d "${var_projects_path}" ]]; then
    msg_error "Directory '${var_projects_path}' does not exist on this Proxmox host!"
    exit 1
  fi
  if awk -v p="${var_projects_path}" '$1 == "path" && $2 == p {found = 1} END {exit !found}' /etc/pve/storage.cfg 2>/dev/null; then
    msg_error "'${var_projects_path}' is a Proxmox storage root; choose a subdirectory inside it instead!"
    exit 1
  fi
  if ! mountpoint -q "${var_projects_path}"; then
    echo -e "${INFO}${YW}Note: ${var_projects_path} is not a mountpoint, so it lives on the host root filesystem.${CL}"
  fi
fi

if [[ -z "${var_gh_token}" ]]; then
  echo -e "${INFO}${YW}GitHub account (optional): to authenticate now, create a Personal Access Token at${CL}"
  echo -e "${YW}github.com -> Settings -> Developer settings -> Personal access tokens (scope 'repo').${CL}"
  echo -e "${YW}Skip this to authenticate later inside the container with 'gh auth login'.${CL}"
  read -rsp "  GitHub PAT (Enter to skip): " -t 120 var_gh_token || var_gh_token=""
  echo ""
fi

export var_hostname var_projects_mode var_projects_path var_projects_storage var_projects_size var_gh_token

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if ! command -v gentle-shell &>/dev/null; then
    msg_error "No ${APP} Installation Found!"
    exit 1
  fi

  RELEASE=$(npm view gentle-pi version 2>/dev/null)
  if [[ -z "${RELEASE}" ]]; then
    msg_error "Unable to reach npm for the latest gentle-pi version."
    exit 1
  fi
  msg_info "Updating ${APP} (gentle-pi@${RELEASE})"
  $STD npm install -g "gentle-pi@${RELEASE}"
  msg_ok "Updated ${APP}"
  exit
}

start
build_container

if [[ "${var_projects_mode}" == "external" ]]; then
  msg_info "Attaching Projects Volume (${var_projects_storage}:${var_projects_size}GB)"
  pct set "${CTID}" -mp0 "${var_projects_storage}:${var_projects_size},mp=/mnt/projects"
  if ! pct exec "${CTID}" -- mountpoint -q /mnt/projects 2>/dev/null; then
    pct reboot "${CTID}"
    for _ in {1..30}; do
      pct exec "${CTID}" -- mountpoint -q /mnt/projects 2>/dev/null && break
      sleep 2
    done
  fi
  if ! pct exec "${CTID}" -- mountpoint -q /mnt/projects 2>/dev/null; then
    msg_error "Projects mountpoint on '${var_projects_storage}' did not activate; check the container config."
    exit 1
  fi
  pct exec "${CTID}" -- ln -sfn /mnt/projects /root/projects
  msg_ok "Attached Projects Volume"
fi

if [[ "${var_projects_mode}" == "bind" ]]; then
  msg_info "Attaching Projects Directory (${var_projects_path})"
  pct set "${CTID}" -mp0 "${var_projects_path},mp=/mnt/projects"
  _proj_ready=false
  if pct exec "${CTID}" -- mountpoint -q /mnt/projects 2>/dev/null; then
    _proj_ready=true
  else
    pct reboot "${CTID}"
    for _ in {1..30}; do
      if pct exec "${CTID}" -- mountpoint -q /mnt/projects 2>/dev/null; then
        _proj_ready=true
        break
      fi
      sleep 2
    done
  fi
  if [[ "${_proj_ready}" == "false" ]]; then
    msg_error "Projects directory '${var_projects_path}' did not mount; check the container config."
    exit 1
  fi
  if ! pct exec "${CTID}" -- sh -c 'touch /mnt/projects/.cs-write-test && rm -f /mnt/projects/.cs-write-test' 2>/dev/null; then
    echo -e "${INFO}${YW}Warning: the projects directory is not writable inside the container. Run 'chown -R 100000:100000 \"${var_projects_path}\"' on the Proxmox host.${CL}"
  fi
  pct exec "${CTID}" -- ln -sfn /mnt/projects /root/projects
  msg_ok "Attached Projects Directory"
fi

description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW}Connect via SSH (root) and run 'gentle-shell'; projects live in /root/projects.${CL}"
