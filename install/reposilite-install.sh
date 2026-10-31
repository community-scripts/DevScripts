#!/usr/bin/env bash
# Copyright (c) 2026
# Author: hwajin-me
# License: MIT
# Source: https://reposilite.com/guide/general

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
catch_errors
setting_up_container
network_check
update_os

setup_alpine() {
  JAVA_VERSION="21" setup_java
  msg_info "Installing Reposilite dependencies"
  $STD apk add --no-cache tzdata
  msg_ok "Installed Reposilite dependencies"

  # GitHub releases link to Maven-hosted JARs and have no GitHub binary assets.
  # fetch_and_deploy_from_url extracts ZIPs, which would unpack a runnable JAR.
  RELEASE="${APPLICATION_VERSION:-$(get_latest_github_release "dzikoysk/reposilite")}"
  [[ "$RELEASE" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { msg_error "Invalid Reposilite release"; exit 1; }
  mkdir -p /opt/reposilite "$var_data_dir" /var/log/reposilite
  URL="https://maven.reposilite.com/releases/com/reposilite/reposilite/${RELEASE}/reposilite-${RELEASE}-all.jar"
  download_file "$URL" /opt/reposilite/reposilite.jar
  download_file "${URL}.sha256" /opt/reposilite/reposilite.jar.sha256
  CHECKSUM="$(cat /opt/reposilite/reposilite.jar.sha256)"
  [[ "$CHECKSUM" =~ ^[[:xdigit:]]{64}$ ]] || { msg_error "Invalid Reposilite checksum"; exit 1; }
  msg_info "Verifying Reposilite download"
  $STD sha256sum -c - <<<"$CHECKSUM  /opt/reposilite/reposilite.jar"
  msg_ok "Verified Reposilite download"
  cat >/root/.reposilite <<EOF
${RELEASE}
EOF

  msg_info "Configuring Reposilite"
  BOOTSTRAP_SECRET="$(random_password 48)"
  umask 077
  cat >/etc/conf.d/reposilite <<EOF
# Initial manager token name: ${var_admin_user}
# Generate a persistent manager token in the dashboard console, then clear bootstrap_secret.
admin_user="${var_admin_user}"
bootstrap_secret="${BOOTSTRAP_SECRET}"
http_port="${var_port}"
data_directory="${var_data_dir}"
java_opts="-Xms32m -Xmx${var_java_heap}m"
EOF
  AUTH_FILE="$(mktemp)"
  cat >"$AUTH_FILE" <<EOF
user = "${var_admin_user}:${BOOTSTRAP_SECRET}"
EOF
  unset BOOTSTRAP_SECRET
  umask 022
  cat >/etc/init.d/reposilite <<'EOF'
#!/sbin/openrc-run
description="Reposilite Maven repository manager"
command="/usr/bin/java"
command_args="${java_opts} -jar /opt/reposilite/reposilite.jar --working-directory=${data_directory:-/var/lib/reposilite} --hostname=0.0.0.0 --port=${http_port:-8080}"
if [ -n "${bootstrap_secret}" ]; then
  command_args="${command_args} --token=${admin_user:-admin}:${bootstrap_secret}"
fi
command_background="yes"
directory="${data_directory:-/var/lib/reposilite}"
pidfile="/run/reposilite.pid"
output_log="/var/log/reposilite/console.log"
error_log="/var/log/reposilite/error.log"
retry="TERM/30/KILL/5"
depend() {
  need net
  after firewall
}
EOF
  chmod 755 /etc/init.d/reposilite
  $STD rc-update add reposilite default
  $STD rc-service reposilite start
  READY=no
  for ((i=0; i<60; i++)); do
    if curl -fsS --max-time 2 "http://127.0.0.1:${var_port}/" >/dev/null 2>&1; then READY=yes; break; fi
    sleep 2
  done
  [[ "$READY" == yes ]] || { msg_error "Reposilite failed to start; inspect /var/log/reposilite"; exit 1; }
  # Seed database-backed settings once, so later dashboard edits survive updates.
  umask 077
  curl -fsS --config "$AUTH_FILE" "http://127.0.0.1:${var_port}/api/settings/domain/maven" -o /opt/reposilite/maven-settings.json
  jq --arg public "$var_public_repositories" --arg private "$var_private_repositories" \
    --arg quota "${var_repository_quota}%" --argjson redeploy "$([[ "$var_redeployment" == yes ]] && echo true || echo false)" \
    --argjson snapshots "$([[ "$var_preserve_snapshots" == yes ]] && echo true || echo false)" \
    --argjson custom "${var_repositories_json:-null}" '
      .repositories = (if $custom != null then $custom else
        [({names: $public, visibility: "PUBLIC"}, {names: $private, visibility: "PRIVATE"}) |
          select(.names != "-") | .visibility as $visibility | .names | split(",")[] |
          {id: ., visibility: $visibility, storageProvider: {type: "fs", quota: $quota, mount: ""},
           redeployment: $redeploy, preserveSnapshots: $snapshots, proxied: []}]
        end)' /opt/reposilite/maven-settings.json >/opt/reposilite/maven-initial.json
  curl -fsS --config "$AUTH_FILE" -X PUT -H 'Content-Type: application/json' \
    --data-binary @/opt/reposilite/maven-initial.json "http://127.0.0.1:${var_port}/api/settings/domain/maven" >/dev/null
  curl -fsS --config "$AUTH_FILE" "http://127.0.0.1:${var_port}/api/settings/domain/frontend" -o /opt/reposilite/frontend-settings.json
  jq --arg title "$var_dashboard_title" --arg description "$var_dashboard_description" \
    '.title = $title | .description = $description' /opt/reposilite/frontend-settings.json >/opt/reposilite/frontend-initial.json
  curl -fsS --config "$AUTH_FILE" -X PUT -H 'Content-Type: application/json' \
    --data-binary @/opt/reposilite/frontend-initial.json "http://127.0.0.1:${var_port}/api/settings/domain/frontend" >/dev/null
  rm -f "$AUTH_FILE" /opt/reposilite/{maven,frontend}-{settings,initial}.json
  umask 022
  msg_ok "Configured Reposilite"
}

run_os_setup
motd_ssh
customize
cleanup_lxc
