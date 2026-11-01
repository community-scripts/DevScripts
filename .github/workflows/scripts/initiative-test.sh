#!/usr/bin/env bash
# Exercise installer failure boundaries without root, network access or a guest.
set -Eeuo pipefail

scripts_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
test_root=$(mktemp -d)
trap 'rm -rf "$test_root"' EXIT
export TASK_TEST_ROOT TEST_CASE TEST_MODE

cat <<'MOCKS' >"$test_root/framework.sh"
color() { :; }
verb_ip6() { :; }
catch_errors() { set -Eeuo pipefail; }
setting_up_container() { :; }
network_check() { :; }
update_os() { :; }
header_info() { :; }
variables() { :; }
check_container_storage() { :; }
check_container_resources() { :; }
msg_info() { :; }
msg_ok() { :; }
msg_warn() { printf 'WARN %s\n' "$*"; }
msg_error() { printf '%s\n' "$*" >&2; }
motd_ssh() { :; }
customize() { :; }
cleanup_lxc() { :; }
description() { :; }
build_container() { :; }
get_os_info() {
  case "$1" in
    id) printf 'debian\n' ;;
    version) [[ "$TEST_CASE" == wrong-os ]] && printf '12\n' || printf '13\n' ;;
  esac
}
random_password() { printf 'TestOnlyGeneratedPassword01234567'; }
setup_postgresql() { printf 'postgresql\n' >>"$TASK_TEST_ROOT/operations"; }
setup_postgresql_db() { printf 'database\n' >>"$TASK_TEST_ROOT/operations"; }
get_latest_github_release() { printf 'v0.76.0\n'; }
check_for_gh_release() {
  CHECK_UPDATE_RELEASE=v0.76.0
  [[ "$TEST_CASE" != no-update ]]
}
fetch_and_deploy_gh_release() {
  [[ "$2" == beyonders-studio/initiative && "$3" == singlefile && "$4" == v0.76.0 ]]
  [[ "${USE_ORIGINAL_FILENAME:-}" == true ]]
  [[ "${FORCE_UPDATE:-}" == 1 ]]
  printf 'fetch %s\n' "$6" >>"$TASK_TEST_ROOT/operations"
  if [[ "$6" == initiative-server_0.76.0-\*_amd64.deb ]]; then
    [[ "$TEST_CASE" != missing-asset ]] || return 252
    printf 'fixture package\n' >"$5/initiative-server_0.76.0-1_amd64.deb"
  elif [[ "$6" == initiative-server-deb-amd64.sha256 ]]; then
    (cd "$5" && sha256sum initiative-server_0.76.0-1_amd64.deb >initiative-server-deb-amd64.sha256)
    if [[ "$TEST_CASE" == corrupt ]]; then
      printf 'corruption\n' >>"$5/initiative-server_0.76.0-1_amd64.deb"
    fi
  else
    return 65
  fi
}
dpkg() { printf 'amd64\n'; }
dpkg-deb() {
  case "$3" in
    Package) [[ "$TEST_CASE" == desktop-package ]] && printf 'initiative\n' || printf 'initiative-server\n' ;;
    Architecture) [[ "$TEST_CASE" == wrong-arch ]] && printf 'arm64\n' || printf 'amd64\n' ;;
  esac
}
apt() {
  printf 'apt %s\n' "${*: -1}" >>"$TASK_TEST_ROOT/operations"
  if [[ "${*: -1}" == *.deb ]]; then
    touch "$TASK_TEST_ROOT/usr/bin/initiative-server"
    chmod +x "$TASK_TEST_ROOT/usr/bin/initiative-server"
    touch "$TASK_TEST_ROOT/unit-changed"
  fi
}
chown() { :; }
systemctl() {
  printf 'systemctl %s\n' "$*" >>"$TASK_TEST_ROOT/operations"
  if [[ "$1" == daemon-reload ]]; then
    rm -f "$TASK_TEST_ROOT/unit-changed"
  elif [[ "$TEST_CASE" == changed-unit && "$*" == *initiative-server* &&
    ( "$1" == start || "$1" == enable ) && -e "$TASK_TEST_ROOT/unit-changed" ]]; then
    return 1
  fi
}
pg_lsclusters() {
  if [[ "$TEST_CASE" == online-cluster ]]; then
    printf '17 main 5432 online postgres /var/lib/postgresql/17/main log\n'
  else
    printf '17 main 5432 down postgres /var/lib/postgresql/17/main log\n'
  fi
}
create_backup() {
  printf 'backup\n' >>"$TASK_TEST_ROOT/operations"
  [[ "$TEST_CASE" != backup-failure ]] || return 1
  [[ -d "$BACKUP_DIR" ]]
}
create_self_signed_cert() { :; }
nginx_enable_site() { :; }
curl() {
  [[ " $* " == *" --fail-with-body "* ]] || return 2
  [[ "$TEST_CASE" != unready ]] || return 22
  while (($#)); do
    if [[ "$1" == --output ]]; then
      case "$TEST_CASE" in
        degraded)
          printf '{"status":"degraded","checks":{"database":"ok","database_system":"ok","database_provisioning":"ok","notify_bus":"error","storage":"ok","rate_limit_store":"ok"}}\n' >"$2"
          ;;
        partial-ready)
          printf '{"status":"ok","checks":{"database":"ok","database_system":"ok","database_provisioning":"ok","notify_bus":"error"}}\n' >"$2"
          ;;
        required-error)
          printf '{"status":"degraded","checks":{"database":"error","database_system":"ok","database_provisioning":"ok","notify_bus":"ok"}}\n' >"$2"
          ;;
        missing-database)
          printf '{"status":"ok","checks":{"notify_bus":"ok"}}\n' >"$2"
          ;;
        invalid-ready) printf '<html>unexpected response</html>\n' >"$2" ;;
        empty-ready) : >"$2" ;;
        unavailable)
          printf '{"status":"unavailable","checks":{"database":"error","database_system":"ok","database_provisioning":"ok"}}\n' >"$2"
          return 22
          ;;
        duplicate-ready)
          printf '%s\n' '{"status":"ok","checks":{"database":"ok","database_system":"ok","database_provisioning":"ok"}}' '{"status":"ok","checks":{"database":"ok","database_system":"ok","database_provisioning":"ok"}}' >"$2"
          ;;
        *)
          printf '{"status":"ok","checks":{"database":"ok","database_system":"ok","database_provisioning":"ok","notify_bus":"ok","storage":"ok","rate_limit_store":"ok"}}\n' >"$2"
          ;;
      esac
      return
    fi
    shift
  done
  return 1
}
start() { [[ "$TEST_MODE" != update ]] || update_script; }
STD=""
LOCAL_IP=192.0.2.10
IP=192.0.2.10
CREATING="" GN="" CL="" INFO="" YW="" GATEWAY="" BGN=""
MOCKS

run_case() {
  TEST_CASE=$1
  TEST_MODE=$2
  TASK_TEST_ROOT="$test_root/$TEST_CASE-$TEST_MODE"
  mkdir -p "$TASK_TEST_ROOT"/{opt,etc/initiative,etc/nginx/sites-available,var/lib/initiative,usr/bin,root,framework/core}
  cp "$test_root/framework.sh" "$TASK_TEST_ROOT/framework/core/build.func"
  touch "$TASK_TEST_ROOT/operations"
  local script
  if [[ "$TEST_MODE" == update ]]; then
    script=ct/initiative.sh
    printf 'retained configuration\n' >"$TASK_TEST_ROOT/etc/initiative/server.env"
    printf '0.75.0\n' >"$TASK_TEST_ROOT/root/.initiative"
    touch "$TASK_TEST_ROOT/usr/bin/initiative-server"
    chmod +x "$TASK_TEST_ROOT/usr/bin/initiative-server"
  else
    script=install/initiative-install.sh
  fi
  sed \
    -e "s|/etc/initiative|$TASK_TEST_ROOT/etc/initiative|g" \
    -e "s|/etc/nginx|$TASK_TEST_ROOT/etc/nginx|g" \
    -e "s|/etc/postgresql|$TASK_TEST_ROOT/etc/postgresql|g" \
    -e "s|/var/lib/initiative|$TASK_TEST_ROOT/var/lib/initiative|g" \
    -e "s|/var/lib/postgresql|$TASK_TEST_ROOT/var/lib/postgresql|g" \
    -e "s|/usr/bin/initiative-server|$TASK_TEST_ROOT/usr/bin/initiative-server|g" \
    -e "s|/opt/|$TASK_TEST_ROOT/opt/|g" \
    -e "s|\${HOME}/.initiative|\${TASK_TEST_ROOT}/root/.initiative|g" \
    "$scripts_root/$script" >"$TASK_TEST_ROOT/script.sh"
  local result=0
  FUNCTIONS_FILE_PATH="$(cat "$test_root/framework.sh")" \
    COMMUNITY_SCRIPTS_CORE_DIR="$TASK_TEST_ROOT/framework" \
    bash "$TASK_TEST_ROOT/script.sh" >"$TASK_TEST_ROOT/output" 2>&1 || result=$?
  if [[ "$3" == pass && "$result" != 0 ]] || [[ "$3" == fail && "$result" == 0 ]]; then
    cat "$TASK_TEST_ROOT/output" >&2
    printf 'FAIL %s %s (exit %s)\n' "$TEST_MODE" "$TEST_CASE" "$result" >&2
    exit 1
  fi
}

assert_no_operation() {
  if grep -q "$1" "$TASK_TEST_ROOT/operations"; then
    printf 'Unexpected operation in %s: %s\n' "$TEST_CASE" "$1" >&2
    exit 1
  fi
}

for scenario in corrupt desktop-package wrong-arch missing-asset wrong-os; do
  run_case "$scenario" install fail
  assert_no_operation '^apt .*\.deb$'
  assert_no_operation '^systemctl .*initiative-server'
  [[ ! -e "$TASK_TEST_ROOT/root/.initiative" ]]
  printf 'PASS install rejects %s before package activation\n' "$scenario"
done

for scenario in unready partial-ready required-error missing-database invalid-ready empty-ready unavailable duplicate-ready; do
  run_case "$scenario" install fail
  [[ ! -e "$TASK_TEST_ROOT/root/.initiative" ]]
  printf 'PASS %s first startup does not record an installed version\n' "$scenario"
done

run_case valid install pass
[[ "$(cat "$TASK_TEST_ROOT/root/.initiative")" == 0.76.0 ]]
grep -q '^ENABLE_PUBLIC_REGISTRATION=false$' "$TASK_TEST_ROOT/etc/initiative/server.env"
grep -q '^INITIATIVE_HOST=127.0.0.1$' "$TASK_TEST_ROOT/etc/initiative/server.env"
printf 'PASS successful install records the version after readiness\n'

for install_mode in install update; do
  run_case degraded "$install_mode" pass
  [[ "$(cat "$TASK_TEST_ROOT/root/.initiative")" == 0.76.0 ]]
  grep -q '^WARN .*notify_bus' "$TASK_TEST_ROOT/output"
  printf 'PASS %s accepts ready-but-degraded responses with a dependency warning\n' "$install_mode"

  run_case changed-unit "$install_mode" pass
  awk '/^apt .*\.deb$/ { installed = NR } /^systemctl daemon-reload$/ { reload = NR } /^systemctl (start|enable).*initiative-server/ { if (!installed || !reload || installed >= reload || reload >= NR) exit 1; started = 1 } END { if (!started) exit 1 }' "$TASK_TEST_ROOT/operations"
  printf 'PASS %s reloads the installed unit before starting Initiative\n' "$install_mode"
done

for scenario in corrupt backup-failure online-cluster; do
  run_case "$scenario" update fail
  assert_no_operation '^apt .*\.deb$'
  [[ "$(cat "$TASK_TEST_ROOT/root/.initiative")" == 0.75.0 ]]
  printf 'PASS update rejects %s before package replacement\n' "$scenario"
done

for scenario in unready partial-ready required-error missing-database invalid-ready empty-ready unavailable duplicate-ready; do
  run_case "$scenario" update fail
  [[ "$(cat "$TASK_TEST_ROOT/root/.initiative")" == 0.75.0 ]]
  printf 'PASS %s update retains the previous installed version\n' "$scenario"
done

run_case no-update update pass
[[ ! -s "$TASK_TEST_ROOT/operations" ]]
printf 'PASS current installation performs no package or service operations\n'

run_case valid update pass
[[ "$(cat "$TASK_TEST_ROOT/root/.initiative")" == 0.76.0 ]]
[[ "$(cat "$TASK_TEST_ROOT/etc/initiative/server.env")" == 'retained configuration' ]]
awk '/^backup$/ { backup = NR } /^apt .*\.deb$/ { if (!backup || backup >= NR) exit 1; installed = 1 } END { if (!installed) exit 1 }' "$TASK_TEST_ROOT/operations"
printf 'PASS successful update backs up before replacing the package\n'

# Run the operator's documented recovery, including a failed transfer with valid JSON.
for recovery_case in valid reload-failure transfer-failure database-failure; do
  (
    TASK_TEST_ROOT="$test_root/recovery-$recovery_case"
    TEST_CASE=$recovery_case
    mkdir -p "$TASK_TEST_ROOT"/{root,usr/lib/initiative}
    printf '0.77.1\n' >"$TASK_TEST_ROOT/usr/lib/initiative/VERSION"
    printf '0.76.0\n' >"$TASK_TEST_ROOT/root/.initiative"
    # shellcheck disable=SC2329 # Exported into the child Bash process below.
    systemctl() { [[ "$TEST_CASE" != reload-failure ]]; }
    # shellcheck disable=SC2329 # Exported into the child Bash process below.
    curl() {
      if [[ "$TEST_CASE" == database-failure ]]; then
        printf '{"status":"unavailable","checks":{"database":"error","database_system":"ok","database_provisioning":"ok"}}\n'
      else
        printf '{"status":"ok","checks":{"database":"ok","database_system":"ok","database_provisioning":"ok"}}\n'
      fi
      [[ "$TEST_CASE" != transfer-failure ]]
    }
    export -f systemctl curl
    awk '
      /^### Recover an upgrade/ { section = 1 }
      section && /^```bash/ { capture = 1; next }
      capture && /^```/ { exit }
      capture { print }
    ' "$scripts_root/docs/guides/initiative.md" |
      sed -e "s|/root/.initiative|$TASK_TEST_ROOT/root/.initiative|g" \
        -e "s|/usr/lib/initiative|$TASK_TEST_ROOT/usr/lib/initiative|g" >"$TASK_TEST_ROOT/recovery.sh"
    result=0
    bash "$TASK_TEST_ROOT/recovery.sh" || result=$?
    if [[ "$TEST_CASE" == valid ]]; then
      [[ "$result" == 0 && "$(cat "$TASK_TEST_ROOT/root/.initiative")" == 0.77.1 ]]
    else
      [[ "$result" != 0 && "$(cat "$TASK_TEST_ROOT/root/.initiative")" == 0.76.0 ]]
    fi
    printf 'PASS documented recovery %s preserves its version-marker gates\n' "$TEST_CASE"
  )
done
