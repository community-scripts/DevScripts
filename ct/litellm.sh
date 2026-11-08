#!/usr/bin/env bash
_CS_DEFAULT_URL="https://raw.githubusercontent.com/community-scripts/DevScripts/main"
_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../core}/core/build.func"
source "$_cs_boot" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/build.func")
# Copyright (c) 2021-2026 community-scripts ORG
# Author: stout01
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://github.com/BerriAI/litellm

APP="LiteLLM"
var_tags="${var_tags:-ai;interface}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-8}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"
export var_litellm_http="${var_litellm_http:-yes}"
export var_litellm_version="1.108.0"
export var_litellm_prisma_version="0.11.0"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  local venv_path="/opt/litellm/.venv"
  local recovery_file="/opt/litellm/.upgrade-backup"
  local upgrade_lock
  exec {upgrade_lock}>/run/lock/litellm-update.lock
  if ! flock -n "$upgrade_lock"; then
    msg_error "A LiteLLM upgrade is already running."
    exit 1
  fi
  if [[ -f "$recovery_file" ]]; then
    msg_error "An earlier LiteLLM upgrade needs recovery. Backups are in $(<"$recovery_file")."
    exit 1
  fi
  if [[ ! -x "$venv_path/bin/python" || ! -f /opt/litellm/.env || ! -f /opt/litellm/litellm.yaml || ! -f /etc/systemd/system/litellm.service ]]; then
    msg_error "LiteLLM upgrades require the managed systemd installation with /opt/litellm/.env."
    exit 1
  fi

  local update_url="$COMMUNITY_SCRIPTS_URL"
  local current_versions current_version current_prisma_version
  current_versions=$("$venv_path/bin/python" -c 'from importlib.metadata import version; print(version("litellm"), version("prisma"))')
  IFS=' ' read -r current_version current_prisma_version <<<"$current_versions"
  if should_upgrade "$var_litellm_version" "$current_version"; then
    msg_error "LiteLLM $current_version is newer than the supported target $var_litellm_version."
    exit 1
  fi
  if [[ "$current_version" == "$var_litellm_version" && "$current_prisma_version" == "$var_litellm_prisma_version" ]]; then
    write_update_entrypoint "${SCRIPT_SLUG:-litellm}" "litellm" "$update_url"
    msg_ok "LiteLLM $current_version and Prisma $current_prisma_version are up to date."
    exit 0
  fi
  if ! awk '
    /^[[:space:]]*DATABASE_URL[[:space:]]*=/ { assignments++ }
    /^DATABASE_URL=postgresql:\/\/litellm:[[:alnum:]]+@127\.0\.0\.1:5432\/litellm_db$/ { local_database++ }
    END { exit !(assignments == 1 && local_database == 1) }
  ' /opt/litellm/.env ||
    ! "$venv_path/bin/python" -c 'import sys, yaml; settings = (yaml.safe_load(sys.stdin) or {}).get("general_settings") or {}; sys.exit(settings.get("database_url") != "os.environ/DATABASE_URL")' </opt/litellm/litellm.yaml; then
    msg_error "LiteLLM upgrades require the managed local PostgreSQL database so it can be backed up."
    exit 1
  fi
  if ! systemctl is-active --quiet litellm; then
    msg_error "Start the existing LiteLLM service before upgrading."
    exit 1
  fi
  if ! command -v uv >/dev/null; then
    PYTHON_VERSION="3.13" setup_uv
  fi

  msg_info "Preparing LiteLLM $var_litellm_version with Prisma $var_litellm_prisma_version"
  local new_venv schema_path
  new_venv=$(mktemp -d /opt/litellm/.venv-next.XXXXXX)
  if ! {
    $STD uv venv --relocatable --python 3.13 "$new_venv" &&
      $STD uv pip install --python "$new_venv/bin/python" "litellm[proxy,extra-proxy]==$var_litellm_version" "prisma==$var_litellm_prisma_version" &&
      schema_path=$("$new_venv/bin/python" -c 'from importlib.util import find_spec; from pathlib import Path; print(Path(find_spec("litellm").origin).parent / "proxy" / "schema.prisma")') &&
      $STD env "PATH=$new_venv/bin:$PATH" "$new_venv/bin/prisma" generate --schema="$schema_path"
  }; then
    rm -rf -- "$new_venv"
    msg_error "Could not prepare the LiteLLM upgrade."
    exit 1
  fi
  msg_ok "Prepared LiteLLM and Generated the Prisma Client"

  local backup_dir
  backup_dir=$(mktemp -d /opt/litellm-backup.XXXXXX)
  BACKUP_DIR="$backup_dir" create_backup /opt/litellm/.env /opt/litellm/litellm.yaml
  cat <<EOF >"$recovery_file"
$backup_dir
EOF

  msg_info "Backing Up the LiteLLM PostgreSQL Database"
  systemctl stop litellm
  if ! runuser -u postgres -- pg_dump --host=/var/run/postgresql --port=5432 --username=postgres --no-password --format=custom --dbname=litellm_db >"$backup_dir/postgresql.dump"; then
    systemctl start litellm
    rm -rf -- "$new_venv"
    rm -f -- "$recovery_file"
    msg_error "Could not back up the LiteLLM database. The original service has been restarted."
    exit 1
  fi
  msg_ok "Backed Up the LiteLLM Database to $backup_dir/postgresql.dump"

  msg_info "Starting the Upgraded LiteLLM Service"
  if ! mv -T -- "$venv_path" "$backup_dir/venv"; then
    systemctl start litellm
    rm -rf -- "$new_venv"
    rm -f -- "$recovery_file"
    msg_error "Could not move the existing LiteLLM environment. The original service has been restarted."
    exit 1
  fi
  if ! mv -T -- "$new_venv" "$venv_path"; then
    mv -T -- "$backup_dir/venv" "$venv_path"
    systemctl start litellm
    rm -rf -- "$new_venv"
    rm -f -- "$recovery_file"
    msg_error "Could not activate the new LiteLLM environment. The original service has been restarted."
    exit 1
  fi
  if (
    set -o pipefail
    systemctl start litellm || exit 1
    deadline=$((SECONDS + 180))
    until curl -fsS --max-time 5 http://127.0.0.1:4000/health/readiness 2>/dev/null | jq -e '.db == "connected"' >/dev/null; do
      ((SECONDS < deadline)) || exit 1
      sleep 2
    done
  ); then
    rm -f -- "$recovery_file"
    write_update_entrypoint "${SCRIPT_SLUG:-litellm}" "litellm" "$update_url"
    msg_ok "Upgraded LiteLLM to $var_litellm_version with Prisma $var_litellm_prisma_version"
    exit 0
  fi

  systemctl stop litellm
  if [[ "$current_version" == "$var_litellm_version" ]]; then
    mv -T -- "$venv_path" "$new_venv"
    mv -T -- "$backup_dir/venv" "$venv_path"
    systemctl start litellm
    rm -rf -- "$new_venv"
    rm -f -- "$recovery_file"
    msg_error "LiteLLM upgrade failed. The previous environment was restored. See journalctl -u litellm."
  else
    msg_error "LiteLLM upgrade failed and the service was stopped. The previous environment and PostgreSQL backup are in $backup_dir."
  fi
  exit 1
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}LiteLLM setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW}Access it using the following URL:${CL}"
echo -e "${GATEWAY}${BGN}https://${IP}/ui${CL}"
if [[ "$var_litellm_http" == "yes" ]]; then
  echo -e "${INFO}${YW}HTTP access is also enabled on port 80.${CL}"
fi
echo -e "${INFO}${YW}Log in to LiteLLM as admin with LITELLM_MASTER_KEY from /opt/litellm/.env inside the container.${CL}"
