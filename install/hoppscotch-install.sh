#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://github.com/hoppscotch/hoppscotch

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt install -y caddy
msg_ok "Installed Dependencies"

setup_postgresql
PG_DB_NAME="hoppscotch" PG_DB_USER="hoppscotch" PG_DB_CREDS_FILE="/dev/null" setup_postgresql_db
setup_go
fetch_and_deploy_gh_release "hoppscotch" "hoppscotch/hoppscotch" "tarball"
NODE_VERSION="24" NODE_MODULE="$(jq -r '.packageManager' /opt/hoppscotch/package.json)" setup_nodejs

msg_info "Configuring Hoppscotch"
mkdir -p /opt/hoppscotch_data/webapp-server
cat <<EOF >/opt/hoppscotch_data/.env
DATABASE_URL=postgresql://hoppscotch:${PG_DB_PASS}@localhost:5432/hoppscotch
DATA_ENCRYPTION_KEY=$(openssl rand -hex 16)
WHITELISTED_ORIGINS=http://${LOCAL_IP},app://${LOCAL_IP//./_},app://hoppscotch
ENABLE_SUBPATH_BASED_ACCESS=true
PRODUCTION=true
PORT=8080
EOF
chmod 600 /opt/hoppscotch_data/.env
cat <<EOF >/opt/hoppscotch_data/frontend.env
VITE_BASE_URL=http://${LOCAL_IP}
VITE_SHORTCODE_BASE_URL=http://${LOCAL_IP}
VITE_ADMIN_URL=http://${LOCAL_IP}/admin
VITE_BACKEND_GQL_URL=http://${LOCAL_IP}/backend/graphql
VITE_BACKEND_WS_URL=ws://${LOCAL_IP}/backend/graphql
VITE_BACKEND_API_URL=http://${LOCAL_IP}/backend/v1
VITE_APP_TOS_LINK=https://docs.hoppscotch.io/support/terms
VITE_APP_PRIVACY_POLICY_LINK=https://docs.hoppscotch.io/support/privacy
EOF
ln -sf /opt/hoppscotch_data/frontend.env /opt/hoppscotch/.env
ln -sf /opt/hoppscotch_data/.env /opt/hoppscotch/packages/hoppscotch-backend/.env
msg_ok "Configured Hoppscotch"

msg_info "Building Hoppscotch"
cd /opt/hoppscotch
$STD pnpm install --frozen-lockfile
cd /opt/hoppscotch/packages/hoppscotch-backend
$STD pnpm exec prisma generate
$STD pnpm run build
$STD pnpm exec prisma migrate deploy
cd /opt/hoppscotch/packages/hoppscotch-selfhost-web
HOPP_ALLOW_RUNTIME_ENV=true $STD pnpm run build --sourcemap false
cd /opt/hoppscotch/packages/hoppscotch-selfhost-web/webapp-server
CGO_ENABLED=0 $STD go build -o webapp-server .
$STD go clean -cache -modcache
cd /opt/hoppscotch/packages/hoppscotch-sh-admin
HOPP_ALLOW_RUNTIME_ENV=true $STD pnpm run build --outDir dist-subpath-access --base /admin/
msg_ok "Built Hoppscotch"

msg_info "Creating Services"
cat <<'EOF' >/etc/caddy/Caddyfile
:80 {
	handle_path /admin* {
		root * /opt/hoppscotch/packages/hoppscotch-sh-admin/dist-subpath-access
		try_files {path} /
		file_server
	}

	handle_path /backend* {
		@mock header_regexp host Host ^[^.]+\.mock\..*$
		handle @mock {
			rewrite * /mock{uri}
			reverse_proxy 127.0.0.1:8080
		}
		handle {
			reverse_proxy 127.0.0.1:8080
		}
	}

	handle_path /desktop-app-server* {
		reverse_proxy 127.0.0.1:3200
	}

	handle {
		root * /opt/hoppscotch/packages/hoppscotch-selfhost-web/dist
		try_files {path} /
		file_server
	}
}
EOF
cat <<EOF >/etc/systemd/system/hoppscotch-backend.service
[Unit]
Description=Hoppscotch Backend
After=network.target postgresql.service
Wants=postgresql.service

[Service]
Type=simple
WorkingDirectory=/opt/hoppscotch/packages/hoppscotch-backend
EnvironmentFile=/opt/hoppscotch_data/.env
EnvironmentFile=/opt/hoppscotch_data/frontend.env
ExecStart=/usr/bin/node dist/src/main.js
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
cat <<EOF >/etc/systemd/system/hoppscotch-webapp.service
[Unit]
Description=Hoppscotch Webapp Server
After=network.target

[Service]
Type=simple
Environment=FRONTEND_PATH=/opt/hoppscotch/packages/hoppscotch-selfhost-web/dist
Environment=WEBAPP_SERVER_SIGNING_KEY_FILE=/opt/hoppscotch_data/webapp-server/signing.key
ExecStartPre=/opt/hoppscotch/packages/hoppscotch-sh-admin/node_modules/.bin/import-meta-env -x /opt/hoppscotch_data/frontend.env -e /opt/hoppscotch_data/frontend.env -p "/opt/hoppscotch/packages/hoppscotch-selfhost-web/dist/**/*" "/opt/hoppscotch/packages/hoppscotch-sh-admin/dist-subpath-access/**/*"
ExecStart=/opt/hoppscotch/packages/hoppscotch-selfhost-web/webapp-server/webapp-server
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now hoppscotch-backend hoppscotch-webapp
systemctl reload caddy
msg_ok "Created Services"

if [[ -n "${var_smtp_url:-}" && -n "${var_mail_from:-}" ]]; then
  msg_info "Enabling Email Login"
  $STD curl -fsS --retry 30 --retry-all-errors --retry-delay 3 -X POST http://127.0.0.1:8080/v1/onboarding/config \
    -H "Content-Type: application/json" \
    -d "$(jq -n --arg url "$var_smtp_url" --arg from "$var_mail_from" '{VITE_ALLOWED_AUTH_PROVIDERS: "EMAIL", MAILER_SMTP_ENABLE: "true", MAILER_USE_CUSTOM_CONFIGS: "false", MAILER_SMTP_URL: $url, MAILER_ADDRESS_FROM: $from}')"
  msg_ok "Enabled Email Login"
fi

motd_ssh
customize
cleanup_lxc
