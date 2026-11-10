#!/usr/bin/env bash
# Build one ct/ script from a pull request on this Proxmox host, check that the
# container really works, destroy it, and leave a result.json behind.
#
# Runs on the self-hosted runner, which *is* the disposable test host. The
# harness comes from the default branch; only the script under test comes from
# the pull request, pinned to the commit a maintainer approved.
#
# The engine hardcodes raw.githubusercontent.com/<upstream>/main for every fetch
# (ct -> build.func -> install script -> install.func -> tools.func). Pointing it
# at a fork branch therefore means rewriting those URLs: the PR tree is unpacked
# under SERVE_ROOT, every upstream main URL in it is replaced by this host's own
# HTTP server, and the containers fetch from there. Engine changes in the PR are
# tested along with the script, which is what a reviewer wants anyway.

set -uo pipefail

: "${PR_REPO:?}" "${PR_SHA:?}" "${SCRIPT:?}" "${UPSTREAM:?}" "${CTID_BASE:?}" "${OUT_DIR:?}"
OS="${OS:-}"
CTID_COUNT="${CTID_COUNT:-50}"
SERVE_ROOT="${SERVE_ROOT:-/srv/ci}"
SERVE_URL="${SERVE_URL:-http://10.99.0.1:18080}"
BRIDGE="${BRIDGE:-vmbr1}"
BUILD_TIMEOUT="${BUILD_TIMEOUT:-45m}"
URL_WAIT="${URL_WAIT:-120}"

# Every value below reaches a path, a URL or a command line.
[[ "$PR_REPO" =~ ^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$ ]] || { echo "bad PR_REPO" >&2; exit 2; }
[[ "$UPSTREAM" =~ ^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$ ]] || { echo "bad UPSTREAM" >&2; exit 2; }
[[ "$PR_SHA" =~ ^[0-9a-f]{40}$ ]] || { echo "bad PR_SHA" >&2; exit 2; }
[[ "$SCRIPT" =~ ^ct/[A-Za-z0-9._-]+\.sh$ ]] || { echo "bad SCRIPT" >&2; exit 2; }
[[ -z "$OS" || "$OS" =~ ^(debian|ubuntu|alpine)$ ]] || { echo "bad OS" >&2; exit 2; }
[[ "$CTID_BASE" =~ ^[0-9]+$ ]] || { echo "bad CTID_BASE" >&2; exit 2; }

mkdir -p "$OUT_DIR"
RAW_LOG="$OUT_DIR/build.raw.log"
LOG="$OUT_DIR/build.log"
RESULT="$OUT_DIR/result.json"
INSTALL_LOG_OUT="$OUT_DIR/install.log"

app=$(basename "$SCRIPT" .sh)
job="${GITHUB_RUN_ID:-local}-${GITHUB_RUN_ATTEMPT:-1}-${app}-${OS:-default}"
tree="$SERVE_ROOT/$job"
base="$SERVE_URL/$job"
started=$(date +%s)

status="fail"
step=""
exit_code=""
ctid=""
ct_ip=""
url=""
http_code=""
failed_units=""

strip_ansi() {
  sed -E 's/\x1B\[[0-9;?]*[A-Za-z]//g; s/\x1B[()][A-Z0-9]//g; s/\r/\n/g' | grep -vE '^\s*$'
}

# The install script's own output: everything $STD hides from the build log.
# Both engines write it inside the container as /root/.install-<session>.log;
# dev_mode=keep makes sure a failed container is still there to read it from.
# If it is gone anyway, the copy the engine leaves on the host is the fallback.
collect_install_log() {
  [[ -n "$ctid" ]] || return 0
  # Exactly one build ran in this container, so the newest install log is ours.
  if pct status "$ctid" &>/dev/null &&
    pct exec "$ctid" -- sh -c 'cat "$(ls -t /root/.install-*.log 2>/dev/null | head -n1)"' 2>/dev/null |
    strip_ansi >"$INSTALL_LOG_OUT" && [[ -s "$INSTALL_LOG_OUT" ]]; then
    return 0
  fi
  # The engine names its host-side files after the session: pct_create_<ctid>_<date>_<session>.log
  local sid f
  sid=$(find /tmp -maxdepth 1 -name "pct_create_${ctid}_*.log" -newer "$RAW_LOG.start" -printf '%f\n' 2>/dev/null |
    sed -E 's/.*_([0-9a-f]+)\.log$/\1/' | head -n1)
  [[ -n "$sid" ]] || { rm -f "$INSTALL_LOG_OUT"; return 0; }
  for f in /tmp/*-"${ctid}"-"${sid}".log /var/log/community-scripts/install-"${sid}"-combined-*.log; do
    [[ -s "$f" ]] && { strip_ansi <"$f" >"$INSTALL_LOG_OUT"; return 0; }
  done
  rm -f "$INSTALL_LOG_OUT"
}

finish() {
  [[ -f "$RAW_LOG" ]] && strip_ansi <"$RAW_LOG" >"$LOG"
  [[ -f "$RAW_LOG" ]] && collect_install_log
  jq -n \
    --arg script "$SCRIPT" --arg os "${OS:-default}" --arg status "$status" \
    --arg step "$step" --arg exit_code "$exit_code" --arg sha "$PR_SHA" \
    --arg ctid "$ctid" --arg url "$url" --arg http_code "$http_code" \
    --arg failed_units "$failed_units" \
    --argjson duration "$(($(date +%s) - started))" \
    --arg tail "$([[ -f "$LOG" ]] && tail -n 60 "$LOG")" \
    '{script: $script, os: $os, status: $status, step: $step, exit_code: $exit_code,
      sha: $sha, ctid: $ctid, url: $url, http_code: $http_code,
      failed_units: $failed_units, duration: $duration, log_tail: $tail}' >"$RESULT"
  echo "::group::result"
  jq 'del(.log_tail)' "$RESULT"
  echo "::endgroup::"
}

build_pid=""
cleanup() {
  if [[ -n "$build_pid" ]]; then
    pkill -TERM -P "$build_pid" &>/dev/null || true
    kill -TERM "$build_pid" &>/dev/null || true
    sleep 2
  fi
  if [[ -n "$ctid" ]]; then
    if pct status "$ctid" &>/dev/null; then
      pct stop "$ctid" --skiplock 1 &>/dev/null || true
      pct destroy "$ctid" --purge 1 --force 1 &>/dev/null || true
    fi
    rm -f "/run/ci-jobs/$ctid"
    # What the engine leaves on the host for this container and its session.
    local f sid
    for f in /tmp/pct_create_"${ctid}"_*.log; do
      [[ -f "$f" && "$f" -nt "$RAW_LOG.start" ]] || continue
      sid=$(sed -E 's/.*_([0-9a-f]+)\.log$/\1/' <<<"$f")
      rm -f -- "$f" /tmp/create-lxc-"${sid}".log /tmp/*-"${ctid}"-"${sid}".log
    done
  fi
  rm -f "$RAW_LOG.start"
  rm -rf -- "$tree"
}
trap cleanup EXIT
# A cancelled job sends TERM; without this the EXIT trap would not run.
trap 'exit 143' TERM
trap 'exit 130' INT

fail() {
  step="$1"
  status="fail"
  echo "::error title=${SCRIPT}::${step}"
  finish
  exit 1
}

# --- Reserve a container ID ---------------------------------------------------
# A lock file per ID, not just "first free one", because the engine only creates
# the container minutes later and two jobs would otherwise pick the same ID.
mkdir -p /run/ci-jobs
exec 9>/run/ci-jobs/.lock
flock 9
for ((id = CTID_BASE; id < CTID_BASE + CTID_COUNT; id++)); do
  [[ -e "/run/ci-jobs/$id" ]] && continue
  pvesh get /cluster/nextid --vmid "$id" &>/dev/null || continue
  echo "$job" >"/run/ci-jobs/$id"
  ctid=$id
  break
done
flock -u 9
exec 9>&-
[[ -n "$ctid" ]] || fail "no free container ID in ${CTID_BASE}-$((CTID_BASE + CTID_COUNT - 1))"

# --- Fetch the approved commit and point it at ourselves ------------------------
mkdir -p "$tree"
curl -fsSL --retry 3 "https://codeload.github.com/${PR_REPO}/tar.gz/${PR_SHA}" |
  tar -xz -C "$tree" --strip-components=1 || fail "could not download ${PR_REPO}@${PR_SHA:0:7}"
[[ -f "$tree/$SCRIPT" ]] || fail "${SCRIPT} does not exist at ${PR_SHA:0:7}"

upstream_re="https://raw\.githubusercontent\.com/${UPSTREAM//./\\.}/(refs/heads/)?main"
grep -rlE "$upstream_re" "$tree" --include='*.sh' --include='*.func' |
  xargs -r sed -i -E "s#${upstream_re}#${base}#g"

# --- Build ----------------------------------------------------------------------
echo "Building ${SCRIPT} (${OS:-default OS}) as CT ${ctid} from ${PR_REPO}@${PR_SHA:0:7}"
hostname_safe="ci-$(tr -c 'a-z0-9-\n' '-' <<<"${app,,}" | cut -c1-50)"
build_env=(
  PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
  HOME=/root TERM=dumb LANG=C.UTF-8
  mode=default MODE=default PHS_SILENT=1 DIAGNOSTICS=no
  var_ctid="$ctid" var_hostname="$hostname_safe"
  var_container_storage=local var_template_storage=local var_brg="$BRIDGE"
  "dev_mode=timing,keep" COMMUNITY_SCRIPTS_URL="$base"
)
touch "$RAW_LOG.start"
[[ -n "$OS" ]] && build_env+=(var_os="$OS")

# In the background so that a TERM from a cancelled job is handled at once:
# bash defers traps until a foreground command returns.
env -i "${build_env[@]}" timeout --kill-after=1m "$BUILD_TIMEOUT" \
  bash -c 'bash -c "$(curl -fsSL "$1")"' _ "$base/$SCRIPT" </dev/null >"$RAW_LOG" 2>&1 &
build_pid=$!
wait "$build_pid"
exit_code=$?
build_pid=""

if ((exit_code == 124 || exit_code == 137)); then
  fail "build timed out after ${BUILD_TIMEOUT}"
fi
if ((exit_code != 0)); then
  # The engine marks the step that broke with a cross; that line is the useful one.
  last=$(sed -E 's/\x1B\[[0-9;?]*[A-Za-z]//g; s/\r/\n/g' "$RAW_LOG" | grep -E '✖|\[ERROR\]|error:' | tail -n 1 | sed -E 's/^\s+//' | cut -c1-200)
  fail "build exited ${exit_code}${last:+: $last}"
fi
grep -qi 'completed successfully' "$RAW_LOG" || fail "build exited 0 but never reported success"

# --- Checks ---------------------------------------------------------------------
pct status "$ctid" 2>/dev/null | grep -q running || fail "container ${ctid} is not running"

ct_ip=$(pct exec "$ctid" -- sh -c "ip -4 -o addr show dev eth0 | awk '{print \$4}' | cut -d/ -f1" 2>/dev/null | head -n1)

if pct exec "$ctid" -- sh -c 'command -v systemctl' &>/dev/null; then
  sleep 10
  failed_units=$(pct exec "$ctid" -- systemctl --failed --no-legend --plain 2>/dev/null | awk '{print $1}' | paste -sd, -)
elif pct exec "$ctid" -- sh -c 'command -v rc-status' &>/dev/null; then
  failed_units=$(pct exec "$ctid" -- rc-status --crashed 2>/dev/null | awk '{print $1}' | paste -sd, -)
fi
[[ -z "$failed_units" ]] || fail "failed services: ${failed_units}"

# The URL the script tells the user to open, e.g. http://${IP}:1337/admin
pattern=$(grep -oE 'https?://\$\{IP\}(:[0-9]+)?(/[A-Za-z0-9._~/?=&%-]*)?' "$tree/$SCRIPT" | head -n1)
if [[ -n "$pattern" && -n "$ct_ip" ]]; then
  url="${pattern/\$\{IP\}/$ct_ip}"
  for ((waited = 0; waited < URL_WAIT; waited += 5)); do
    http_code=$(curl -sk -o /dev/null -w '%{http_code}' --max-time 10 "$url" || true)
    [[ "$http_code" =~ ^[1-4][0-9][0-9]$ ]] && break
    sleep 5
  done
  [[ "$http_code" =~ ^[1-4][0-9][0-9]$ ]] || fail "${url} did not answer within ${URL_WAIT}s (last: ${http_code:-none})"
fi

status="pass"
finish
