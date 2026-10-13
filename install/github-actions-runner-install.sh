#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Baker (Baker)
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://github.com/actions/runner

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

setup_deb_based() {
  local repos=() repo owner_repo unit i dest name reg_file reg_token http_code dep

  var_gh_repos="${var_gh_repos//[[:space:]]/}"
  var_runner_count="${var_runner_count:-2}"
  var_runner_name="${var_runner_name:-github-runner}"

  [[ "${var_gh_owner:-}" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || {
    msg_error "GitHub owner is invalid"
    exit 1
  }
  [[ "${var_runner_count}" =~ ^[1-9][0-9]*$ ]] || {
    msg_error "Runners per repository must be a positive integer"
    exit 1
  }
  [[ "${var_runner_name}" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || {
    msg_error "Runner name is invalid"
    exit 1
  }
  [[ -n "${var_gh_token:-}" ]] || {
    msg_error "GitHub token is required"
    exit 1
  }
  [[ -n "${var_gh_repos:-}" ]] || {
    msg_error "At least one repository is required"
    exit 1
  }

  IFS=',' read -r -a repos <<< "${var_gh_repos}"
  for repo in "${repos[@]}"; do
    [[ -n "${repo}" ]] || {
      msg_error "Empty repository name"
      exit 1
    }
    if [[ "${repo}" == */* ]]; then
      owner_repo="${repo}"
    else
      owner_repo="${var_gh_owner}/${repo}"
    fi
    [[ "${owner_repo}" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || {
      msg_error "Repository '${repo}' is invalid"
      exit 1
    }
  done

  msg_info "Installing build tools"
  $STD apt install -y git make gcc libc6-dev
  msg_ok "Installed build tools"

  # Job steps run in containers. The runner binaries stay on the system.
  setup_docker

  fetch_and_deploy_gh_release "github-actions-runner" "actions/runner" "prebuild" "latest" "/opt/actions-runner" "actions-runner-linux-$(arch_resolve "x64" "arm64")-*.tar.gz"

  if [[ -x /opt/actions-runner/bin/installdependencies.sh ]]; then
    dep="/opt/actions-runner/bin/installdependencies.sh"
  elif [[ -x /opt/actions-runner/installdependencies.sh ]]; then
    dep="/opt/actions-runner/installdependencies.sh"
  else
    msg_error "Runner package has no installdependencies.sh"
    exit 1
  fi
  if [[ -f /opt/actions-runner/config.sh ]]; then
    chmod +x /opt/actions-runner/config.sh
  fi
  if [[ -f /opt/actions-runner/bin/runsvc.sh ]]; then
    chmod +x /opt/actions-runner/bin/runsvc.sh
  fi
  if [[ -f "${dep}" ]]; then
    chmod +x "${dep}"
  fi
  msg_info "Installing runner dependencies"
  $STD "${dep}"
  msg_ok "Installed runner dependencies"

  mkdir -p /opt/actions-runners /opt/runner-tool-cache

  msg_info "Registering GitHub Actions runners"
  for repo in "${repos[@]}"; do
    if [[ "${repo}" == */* ]]; then
      owner_repo="${repo}"
    else
      owner_repo="${var_gh_owner}/${repo}"
    fi
    unit="${owner_repo//\//-}"
    for ((i = 1; i <= var_runner_count; i++)); do
      dest="/opt/actions-runners/${unit}-${i}"
      name="${var_runner_name}-${i}"
      mkdir -p "${dest}"
      cp -a /opt/actions-runner/. "${dest}/"
      chmod 700 "${dest}"

      reg_file="$(mktemp)"
      chmod 600 "${reg_file}"
      http_code="$(curl --connect-timeout 10 --max-time 30 -sS -o "${reg_file}" -w '%{http_code}' -X POST \
        -H "Accept: application/vnd.github+json" \
        -H "Authorization: Bearer ${var_gh_token}" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        "https://api.github.com/repos/${owner_repo}/actions/runners/registration-token" || true)"
      reg_token="$(jq -r '.token // empty' "${reg_file}" 2>/dev/null || true)"
      rm -f "${reg_file}"
      if [[ "${http_code}" != "201" || -z "${reg_token}" ]]; then
        unset reg_token
        msg_error "GitHub refused a registration token for ${owner_repo} (HTTP ${http_code})"
        exit 1
      fi

      # config.sh refuses uid 0 unless RUNNER_ALLOW_RUNASROOT is set.
      if ! (
        cd "${dest}"
        RUNNER_ALLOW_RUNASROOT=1 ./config.sh \
          --unattended \
          --replace \
          --url "https://github.com/${owner_repo}" \
          --token "${reg_token}" \
          --name "${name}" \
          --work "_work"
      ) </dev/null; then
        unset reg_token
        msg_error "Could not register ${owner_repo} as ${name}"
        exit 1
      fi
      unset reg_token

      cat <<EOF >"${dest}/.env"
RUNNER_TOOL_CACHE=/opt/runner-tool-cache
EOF
      chmod 600 "${dest}/.env"
      if [[ -f "${dest}/.credentials" ]]; then
        chmod 600 "${dest}/.credentials"
      fi
      if [[ -f "${dest}/.runner" ]]; then
        chmod 600 "${dest}/.runner"
      fi
      chmod 700 "${dest}"

      cat <<EOF >/etc/systemd/system/actions-runner-${unit}-${i}.service
[Unit]
Description=GitHub Actions runner ${i} for ${owner_repo}
After=network-online.target docker.service
Wants=network-online.target docker.service

[Service]
User=root
Environment=RUNNER_ALLOW_RUNASROOT=1
EnvironmentFile=${dest}/.env
ExecStart=${dest}/bin/runsvc.sh
WorkingDirectory=${dest}
KillMode=process
KillSignal=SIGTERM
TimeoutStopSec=5min
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
      systemctl enable -q --now "actions-runner-${unit}-${i}.service"
    done
  done
  msg_ok "Registered GitHub Actions runners"
  unset var_gh_token
}

run_os_setup

motd_ssh
customize
cleanup_lxc
