#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Christian Meier (cm2962)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/ep1cman/unifi-protect-backup

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt install -y \
  ffmpeg \
  rclone
msg_ok "Installed Dependencies"

PYTHON_VERSION="3.11" setup_uv

fetch_and_deploy_gh_release "unifi-protect-backup" "ep1cman/unifi-protect-backup" "tarball"

msg_info "Installing UniFi Protect Backup"
cd /opt/unifi-protect-backup
$STD uv sync --locked --no-editable
msg_ok "Installed UniFi Protect Backup"

if [[ -z "${var_ufp_address:-}" ]]; then
  read -r -p "${TAB3}UniFi Protect address: " var_ufp_address || true
fi
if [[ -z "${var_ufp_address:-}" ]]; then
  msg_error "UniFi Protect address is required (set var_ufp_address or enter it when prompted)"
  exit 64
fi
if [[ -z "${var_ufp_username:-}" ]]; then
  read -r -p "${TAB3}UniFi Protect local username: " var_ufp_username || true
fi
if [[ -z "${var_ufp_username:-}" ]]; then
  msg_error "UniFi Protect local username is required (set var_ufp_username or enter it when prompted)"
  exit 64
fi
if [[ -z "${var_ufp_password:-}" ]]; then
  read -r -s -p "${TAB3}UniFi Protect local password: " var_ufp_password || true
  echo
fi
if [[ -z "${var_ufp_password:-}" ]]; then
  msg_error "UniFi Protect local password is required (set var_ufp_password or enter it when prompted)"
  exit 64
fi

if [[ -z "${var_rclone_retention:-}" ]]; then
  read -r -p "${TAB3}Backup retention (for example 7d, 30d, or 100y) [30d]: " var_rclone_retention || true
fi
var_rclone_retention="${var_rclone_retention:-30d}"
if [[ ! "$var_rclone_retention" =~ ^[0-9]+([.][0-9]+)?(ms|s|m|h|d|w|M|y)$ ]]; then
  msg_error "Invalid backup retention: ${var_rclone_retention}"
  exit 64
fi

if [[ -z "${var_missing_range:-}" ]]; then
  read -r -p "${TAB3}Initial missing-event lookback [1h]: " var_missing_range || true
fi
var_missing_range="${var_missing_range:-1h}"
if [[ ! "$var_missing_range" =~ ^[0-9]+([.][0-9]+)?(ms|s|m|h|d|w|M|y)$ ]]; then
  msg_error "Invalid missing-event lookback: ${var_missing_range}"
  exit 64
fi

var_ufp_ssl_verify="${var_ufp_ssl_verify:-false}"
var_ufp_password="${var_ufp_password//\\/\\\\}"
var_ufp_password="${var_ufp_password//\"/\\\"}"

msg_info "Configuring UniFi Protect Backup"
mkdir -p \
  /opt/unifi-protect-backup/config/database \
  /opt/unifi-protect-backup/config/rclone \
  /var/lib/unifi-protect-backup/clips
cat <<EOF >/opt/unifi-protect-backup/.env
UFP_ADDRESS=${var_ufp_address}
UFP_PORT=443
UFP_USERNAME=${var_ufp_username}
UFP_PASSWORD="${var_ufp_password}"
UFP_SSL_VERIFY=${var_ufp_ssl_verify}
RCLONE_DESTINATION=local:/var/lib/unifi-protect-backup/clips
RCLONE_RETENTION=${var_rclone_retention}
MISSING_RANGE=${var_missing_range}
RCLONE_CONFIG=/opt/unifi-protect-backup/config/rclone/rclone.conf
SQLITE_PATH=/opt/unifi-protect-backup/config/database/events.sqlite
COLOR_LOGGING=false
EOF
cat <<EOF >/opt/unifi-protect-backup/config/rclone/rclone.conf
[local]
type = local
EOF
chmod 600 \
  /opt/unifi-protect-backup/.env \
  /opt/unifi-protect-backup/config/rclone/rclone.conf
msg_ok "Configured UniFi Protect Backup"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/unifi-protect-backup.service
[Unit]
Description=UniFi Protect Backup Service
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/unifi-protect-backup
EnvironmentFile=/opt/unifi-protect-backup/.env
ExecStart=/opt/unifi-protect-backup/.venv/bin/unifi-protect-backup
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now unifi-protect-backup
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc
