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
  mkdir -p /opt/reposilite /var/lib/reposilite /var/log/reposilite
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
# Initial manager token name: admin
# Generate a persistent manager token in the dashboard console, then clear bootstrap_secret.
bootstrap_secret="${BOOTSTRAP_SECRET}"
java_opts="-Xms32m -Xmx256m"
EOF
  unset BOOTSTRAP_SECRET
  umask 022
  cat >/etc/init.d/reposilite <<'EOF'
#!/sbin/openrc-run
description="Reposilite Maven repository manager"
command="/usr/bin/java"
command_args="${java_opts} -jar /opt/reposilite/reposilite.jar --working-directory=/var/lib/reposilite --hostname=0.0.0.0 --port=8080"
if [ -n "${bootstrap_secret}" ]; then
  command_args="${command_args} --token=admin:${bootstrap_secret}"
fi
command_background="yes"
directory="/var/lib/reposilite"
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
    if curl -fsS --max-time 2 http://127.0.0.1:8080/ >/dev/null 2>&1; then READY=yes; break; fi
    sleep 2
  done
  [[ "$READY" == yes ]] || { msg_error "Reposilite failed to start; inspect /var/log/reposilite"; exit 1; }
  msg_ok "Configured Reposilite"
}

run_os_setup
motd_ssh
customize
cleanup_lxc
