#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Jack B-W (jackB-W)
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://github.com/ZimengXiong/PancakeSlicer

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt install -y ffmpeg
msg_ok "Installed Dependencies"

fetch_and_deploy_gh_release "pancakeslicer" "ZimengXiong/PancakeSlicer" "prebuild" "latest" "/opt/pancakeslicer" "PancakeSlicer-*-linux-$(arch_resolve "x64" "arm64").tar.gz"

msg_info "Configuring PancakeSlicer"
mkdir -p /opt/pancakeslicer_data/library /opt/pancakeslicer_data/jobs
cat <<EOF >/opt/pancakeslicer_data/pancakeslicer.env
TZ=UTC
ORCA_WEB_LISTEN=0.0.0.0:6868
ORCA_WEB_MAX_JOBS=2
ORCA_WEB_PRINTER_NETWORK=lan
# ORCA_WEB_BEARER_TOKEN=change-me
EOF
chmod 600 /opt/pancakeslicer_data/pancakeslicer.env
msg_ok "Configured PancakeSlicer"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/pancakeslicer.service
[Unit]
Description=PancakeSlicer
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/pancakeslicer/resources/engine
EnvironmentFile=/opt/pancakeslicer_data/pancakeslicer.env
Environment=HOME=/opt/pancakeslicer_data
Environment=ORCA_WEB_DATA_DIR=/opt/pancakeslicer_data/library
Environment=ORCA_WEB_JOB_ROOT=/opt/pancakeslicer_data/jobs
Environment=ORCA_WEB_STATIC=/opt/pancakeslicer/resources/web
Environment=ORCA_WEB_TOOL=/opt/pancakeslicer/resources/engine/nonplanar_slice_tool
Environment=ORCA_WEB_RESOURCES=/opt/pancakeslicer/resources/engine/resources
Environment=ORCA_WEB_SURFACE_MANIFEST=/opt/pancakeslicer/resources/engine/surface-manifest.json
Environment=ORCA_WEB_ARTIFACT_QUALIFICATION=/opt/pancakeslicer/resources/engine/artifact-qualification.ready
Environment=ORCA_WEB_SOURCE_URL=https://github.com/ZimengXiong/PancakeSlicer/releases/tag/v$(cat ~/.pancakeslicer)
ExecStart=/opt/pancakeslicer/resources/engine/orca-webapp-server
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now pancakeslicer
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc
