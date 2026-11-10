#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: freakms
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://www.xwiki.org

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

XWIKI_DB="${var_xwiki_db:-pgsql}"
XWIKI_CHANNEL="${var_xwiki_channel:-stable}"
XWIKI_XMX="${var_xwiki_xmx:-}"

if [[ "$XWIKI_DB" != "pgsql" && "$XWIKI_DB" != "mariadb" ]]; then
  msg_error "var_xwiki_db must be pgsql or mariadb (given: ${XWIKI_DB})"
  exit 1
fi
if [[ "$XWIKI_CHANNEL" != "stable" && "$XWIKI_CHANNEL" != "lts" ]]; then
  msg_error "var_xwiki_channel must be stable or lts (given: ${XWIKI_CHANNEL})"
  exit 1
fi

# The database server must exist before the XWiki package, so that
# dbconfig-common can create the database and user.
if [[ "$XWIKI_DB" == "pgsql" ]]; then
  setup_postgresql
else
  setup_mariadb
fi

msg_info "Adding XWiki Repository (${XWIKI_CHANNEL})"
curl -fsSL https://maven.xwiki.org/xwiki-keyring.gpg -o /usr/share/keyrings/xwiki-keyring.gpg
curl -fsSL "https://maven.xwiki.org/${XWIKI_CHANNEL}/xwiki-${XWIKI_CHANNEL}.list" -o "/etc/apt/sources.list.d/xwiki-${XWIKI_CHANNEL}.list"
$STD apt update
msg_ok "Added XWiki Repository"

debconf-set-selections <<EOF
dbconfig-common dbconfig-common/dbconfig-install boolean true
dbconfig-common dbconfig-common/remember-admin-pass boolean false
EOF

msg_info "Installing XWiki (Tomcat 10, ${XWIKI_DB})"
export DEBIAN_FRONTEND=noninteractive
$STD apt install -y -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold "xwiki-tomcat10-${XWIKI_DB}"
msg_ok "Installed XWiki"

msg_info "Configuring Java Heap"
if [[ -z "$XWIKI_XMX" ]]; then
  XWIKI_XMX=$(($(awk '/MemTotal/ {print $2}' /proc/meminfo) / 1024 * 60 / 100))
fi
[[ "$XWIKI_XMX" -ge 1024 ]] || XWIKI_XMX=1024
sed -i 's/^\(JAVA_OPTS=.*\)$/#\1/' /etc/default/tomcat10
cat <<EOF >>/etc/default/tomcat10
JAVA_OPTS="-Djava.awt.headless=true -Xmx${XWIKI_XMX}m -XX:+UseG1GC"
EOF
systemctl restart tomcat10
msg_ok "Configured Java Heap (${XWIKI_XMX} MiB)"

msg_info "Waiting for XWiki to start (this can take a few minutes)"
for _ in $(seq 1 90); do
  HTTP_CODE="$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:8080/xwiki/ || true)"
  [[ "$HTTP_CODE" =~ ^(200|302|303)$ ]] && break
  sleep 5
done
if [[ "$HTTP_CODE" =~ ^(200|302|303)$ ]]; then
  msg_ok "XWiki is running"
else
  msg_error "XWiki did not answer (HTTP ${HTTP_CODE}). Check: journalctl -u tomcat10"
  exit 1
fi

motd_ssh
customize
cleanup_lxc
