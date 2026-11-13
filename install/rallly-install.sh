#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://github.com/lukevella/rallly

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

var_admin_email="${var_admin_email:-admin@example.com}"
var_mail_from="${var_mail_from:-$var_admin_email}"
var_smtp_port="${var_smtp_port:-587}"

PG_VERSION="18" setup_postgresql
PG_DB_NAME="rallly" PG_DB_USER="rallly" PG_DB_CREDS_FILE="/dev/null" setup_postgresql_db
fetch_and_deploy_gh_release "rallly" "lukevella/rallly" "tarball"
NODE_VERSION="24" NODE_MODULE="$(jq -r '.packageManager' /opt/rallly/package.json)" setup_nodejs

msg_info "Building Rallly"
cd /opt/rallly
$STD pnpm install --frozen-lockfile
NEXT_PUBLIC_SELF_HOSTED=true NEXT_PUBLIC_APP_VERSION="$(cat ~/.rallly)" SKIP_ENV_VALIDATION=1 NEXT_TELEMETRY_DISABLED=1 $STD pnpm build
cp -r apps/web/.next/static apps/web/.next/standalone/apps/web/.next/
cp -r apps/web/public apps/web/.next/standalone/apps/web/
msg_ok "Built Rallly"

msg_info "Configuring Rallly"
mkdir -p /opt/rallly_data
cat <<EOF >/opt/rallly_data/.env
NODE_ENV=production
PORT=3000
HOSTNAME=0.0.0.0
LOG_LEVEL=warn
NEXT_TELEMETRY_DISABLED=1
DATABASE_URL=postgres://rallly:${PG_DB_PASS}@localhost:5432/rallly
SECRET_PASSWORD=$(random_password 48)
NEXT_PUBLIC_BASE_URL=http://${LOCAL_IP}:3000
SUPPORT_EMAIL=${var_admin_email}
NOREPLY_EMAIL=${var_mail_from}
INITIAL_ADMIN_EMAIL=${var_admin_email}
SMTP_HOST=${var_smtp_host:-}
SMTP_PORT=${var_smtp_port}
SMTP_SECURE=$([[ "$var_smtp_port" == "465" ]] && echo true || echo false)
SMTP_USER=${var_smtp_user:-}
SMTP_PWD=${var_smtp_pass:-}
SMTP_REJECT_UNAUTHORIZED=true
EOF
chmod 600 /opt/rallly_data/.env
DATABASE_URL="$(sed -n 's/^DATABASE_URL=//p' /opt/rallly_data/.env)" $STD pnpm db:deploy
rm -rf node_modules apps/*/node_modules packages/*/node_modules apps/web/.next/cache
msg_ok "Configured Rallly"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/rallly.service
[Unit]
Description=Rallly
After=network-online.target postgresql.service
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=/opt/rallly/apps/web/.next/standalone
EnvironmentFile=/opt/rallly_data/.env
ExecStart=/usr/bin/node apps/web/server.js
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now rallly
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc
