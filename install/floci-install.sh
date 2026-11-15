#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Marc Went (Dunky13)
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://github.com/floci-io/floci

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

JAVA_VERSION="25" setup_java

# after setup_java, so Temurin satisfies maven's Java dependency instead of pulling in OpenJDK
msg_info "Installing Dependencies"
$STD apt install -y maven
msg_ok "Installed Dependencies"

fetch_and_deploy_gh_release "floci" "floci-io/floci" "tarball"

msg_info "Building Floci"
cd /opt/floci
$STD mvn -B clean package -Dmaven.test.skip=true
rm -rf ~/.m2
msg_ok "Built Floci"

msg_info "Configuring Floci"
mkdir -p /opt/floci_data
cat <<EOF >/opt/floci_data/.env
QUARKUS_HTTP_HOST=0.0.0.0
FLOCI_SECURITY_ALLOW_UNSAFE_NETWORK_EXPOSURE=true
FLOCI_BASE_URL=http://${LOCAL_IP}:4566
FLOCI_STORAGE_MODE=persistent
FLOCI_STORAGE_PERSISTENT_PATH=/opt/floci_data/data
FLOCI_SERVICES_UI_ENABLED=false
EOF
msg_ok "Configured Floci"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/floci.service
[Unit]
Description=Floci
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/floci_data
EnvironmentFile=/opt/floci_data/.env
ExecStart=/usr/bin/java --enable-native-access=ALL-UNNAMED -jar /opt/floci/target/quarkus-app/quarkus-run.jar
SuccessExitStatus=143
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now floci
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc
