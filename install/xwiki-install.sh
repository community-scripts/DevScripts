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

setup_postgresql

setup_deb822_repo \
  "xwiki" \
  "https://maven.xwiki.org/xwiki-keyring.gpg" \
  "https://maven.xwiki.org" \
  "stable/"

msg_info "Installing XWiki"
debconf-set-selections <<EOF
dbconfig-common dbconfig-common/dbconfig-install boolean true
dbconfig-common dbconfig-common/remember-admin-pass boolean false
EOF
export DEBIAN_FRONTEND=noninteractive
$STD apt install -y xwiki-tomcat10-pgsql
msg_ok "Installed XWiki"

msg_info "Configuring XWiki"
XWIKI_XMX=$(($(awk '/MemTotal/ {print $2}' /proc/meminfo) * 60 / 100 / 1024))
sed -i 's/^\(JAVA_OPTS=.*\)$/#\1/' /etc/default/tomcat10
cat <<EOF >>/etc/default/tomcat10
JAVA_OPTS="-Djava.awt.headless=true -Xmx${XWIKI_XMX}m -XX:+UseG1GC"
EOF
systemctl restart tomcat10
msg_ok "Configured XWiki"

motd_ssh
customize
cleanup_lxc
