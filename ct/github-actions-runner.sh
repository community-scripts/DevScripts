#!/usr/bin/env bash
_CS_DEFAULT_URL="https://raw.githubusercontent.com/community-scripts/DevScripts/main"
_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../core}/core/build.func"
source "$_cs_boot" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/build.func")

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Baker (Baker)
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://github.com/actions/runner

APP="GitHub-Actions-Runner"
var_tags="${var_tags:-ci;github;actions}"
var_cpu="${var_cpu:-4}"
var_ram="${var_ram:-12288}"
var_disk="${var_disk:-40}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"
# Workflow jobs start containers, so the LXC needs nesting and keyctl.
var_nesting="${var_nesting:-1}"
var_keyctl="${var_keyctl:-1}"

header_info "$APP"
variables
color
catch_errors

# A personal GitHub account cannot share one registration across repositories,
# and each runner process takes one job. Ask on the host, before the container
# exists, so a bad token never creates an LXC. Updates run inside the container
# and only refresh binaries, so they skip this.
_cs_platform=""
declare -f detect_lxc_platform >/dev/null 2>&1 && _cs_platform="$(detect_lxc_platform)"
if [[ "${_cs_platform}" != "container" && "${_cs_platform}" != "incus-container" ]]; then
  if is_unattended; then
    var_runner_count="${var_runner_count:-2}"
    var_runner_name="${var_runner_name:-github-runner}"
    if [[ -z "${var_gh_owner:-}" || -z "${var_gh_repos:-}" || -z "${var_gh_token:-}" ]]; then
      msg_error "Unattended install needs var_gh_owner, var_gh_repos, and var_gh_token"
      exit 1
    fi
  else
    if [[ -z "${var_gh_owner:-}" ]]; then
      var_gh_owner="$(prompt_input_required "GitHub owner" "UNSET" 180 "var_gh_owner")"
    fi
    if [[ -z "${var_gh_repos:-}" ]]; then
      var_gh_repos="$(prompt_input_required "Repositories, comma-separated" "UNSET" 180 "var_gh_repos")"
    fi
    if [[ -z "${var_gh_token:-}" ]]; then
      var_gh_token="$(prompt_password "GitHub token with Administration on each repository" "" 180 20)"
    fi
    if [[ -z "${var_runner_count:-}" ]]; then
      var_runner_count="$(prompt_input "Runners per repository" "2" 120)"
    fi
    if [[ -z "${var_runner_name:-}" ]]; then
      var_runner_name="$(prompt_input "Runner name prefix" "github-runner" 120)"
    fi
  fi

  var_gh_repos="${var_gh_repos//[[:space:]]/}"
  var_runner_count="${var_runner_count:-2}"
  var_runner_name="${var_runner_name:-github-runner}"

  if [[ "${var_gh_owner}" == "UNSET" || ! "${var_gh_owner}" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; then
    msg_error "GitHub owner is invalid"
    exit 1
  fi
  if [[ -z "${var_gh_repos}" || "${var_gh_repos}" == "UNSET" || "${var_gh_repos}" == *,,* || "${var_gh_repos}" == ,* || "${var_gh_repos}" == *, ]]; then
    msg_error "At least one repository is required"
    exit 1
  fi
  if [[ -z "${var_gh_token}" ]]; then
    msg_error "GitHub token is required"
    exit 1
  fi
  if [[ ! "${var_runner_count}" =~ ^[1-9][0-9]*$ ]]; then
    msg_error "Runners per repository must be a positive integer"
    exit 1
  fi
  if [[ ! "${var_runner_name}" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; then
    msg_error "Runner name is invalid"
    exit 1
  fi

  command -v curl >/dev/null 2>&1 || {
    msg_error "curl is required on the host"
    exit 1
  }
  IFS=',' read -r -a _gh_repos <<< "${var_gh_repos}"
  for _gh_repo in "${_gh_repos[@]}"; do
    [[ "${_gh_repo}" == */* ]] || _gh_repo="${var_gh_owner}/${_gh_repo}"
    if [[ ! "${_gh_repo}" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]]; then
      msg_error "Repository name is invalid"
      exit 1
    fi
    _gh_http="$(curl --connect-timeout 10 --max-time 30 -sS -o /dev/null -w '%{http_code}' -X POST \
      -H "Accept: application/vnd.github+json" \
      -H "Authorization: Bearer ${var_gh_token}" \
      -H "X-GitHub-Api-Version: 2022-11-28" \
      "https://api.github.com/repos/${_gh_repo}/actions/runners/registration-token" || true)"
    if [[ "${_gh_http}" != "201" ]]; then
      msg_error "GitHub refused a registration token for ${_gh_repo} (HTTP ${_gh_http}). The token needs Administration on that repository."
      exit 1
    fi
  done
  unset _gh_repos _gh_repo _gh_http
fi

export var_gh_owner="${var_gh_owner:-}"
export var_gh_repos="${var_gh_repos:-}"
export var_gh_token="${var_gh_token:-}"
export var_runner_count="${var_runner_count:-2}"
export var_runner_name="${var_runner_name:-github-runner}"

update_deb_based() {
  if [[ ! -x /opt/actions-runner/config.sh ]]; then
    msg_error "No ${APP} Installation Found!"
    exit 1
  fi

  local unit dest
  if check_for_gh_release "github-actions-runner" "actions/runner"; then
    msg_info "Stopping GitHub Actions Runner"
    shopt -s nullglob
    for unit in /etc/systemd/system/actions-runner-*.service; do
      systemctl stop "$(basename "${unit}")"
    done
    shopt -u nullglob
    msg_ok "Stopped GitHub Actions Runner"

    # Registrations live in /opt/actions-runners and must survive this wipe.
    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "github-actions-runner" "actions/runner" "prebuild" "latest" "/opt/actions-runner" "actions-runner-linux-$(arch_resolve "x64" "arm64")-*.tar.gz"

    msg_info "Updating runner copies"
    shopt -s nullglob
    for dest in /opt/actions-runners/*/; do
      cp -a /opt/actions-runner/. "${dest}"
    done
    shopt -u nullglob
    msg_ok "Updated runner copies"

    if [[ -x /opt/actions-runner/bin/installdependencies.sh ]]; then
      msg_info "Installing runner dependencies"
      $STD /opt/actions-runner/bin/installdependencies.sh
      msg_ok "Installed runner dependencies"
    elif [[ -x /opt/actions-runner/installdependencies.sh ]]; then
      msg_info "Installing runner dependencies"
      $STD /opt/actions-runner/installdependencies.sh
      msg_ok "Installed runner dependencies"
    fi

    msg_info "Starting GitHub Actions Runner"
    shopt -s nullglob
    for unit in /etc/systemd/system/actions-runner-*.service; do
      systemctl start "$(basename "${unit}")"
    done
    shopt -u nullglob
    msg_ok "Started GitHub Actions Runner"
    msg_ok "Updated successfully!"
  fi
  exit
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  run_os_update
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
if [[ -n "${var_gh_repos:-}" ]]; then
  echo -e "${INFO}${YW}Runner settings:${CL}"
  IFS=',' read -r -a _gh_repos <<< "${var_gh_repos//[[:space:]]/}"
  for _gh_repo in "${_gh_repos[@]}"; do
    [[ "${_gh_repo}" == */* ]] || _gh_repo="${var_gh_owner}/${_gh_repo}"
    echo -e "${TAB}${BGN}https://github.com/${_gh_repo}/settings/actions/runners${CL}"
  done
fi
echo -e "${INFO}${YW}Jobs on this container share one network namespace. A workflow that publishes a fixed host port will collide with a second job that publishes the same port.${CL}"
