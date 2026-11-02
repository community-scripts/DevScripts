#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ) | Co-Author: Jan Wiebe Klijnsma (jwklijnsma)
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://aliasvault.net

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt install -y \
  nginx \
  build-essential \
  clang \
  llvm \
  pkg-config \
  libkrb5-3 \
  libgssapi-krb5-2
# Ensure cc linker is available — update-alternatives may not run in minimal LXC
[[ ! -e /usr/bin/cc ]] && ln -sf /usr/bin/gcc /usr/local/bin/cc
msg_ok "Installed Dependencies"

setup_rust
fetch_and_deploy_gh_release "wasm-pack" "rustwasm/wasm-pack" "prebuild" "latest" "/usr/local/bin" "wasm-pack-v*-x86_64-unknown-linux-musl.tar.gz"

NODE_VERSION="22" setup_nodejs

msg_info "Installing .NET SDK 10.0"
setup_deb822_repo "microsoft-prod" \
  "https://packages.microsoft.com/keys/microsoft-2025.asc" \
  "https://packages.microsoft.com/debian/13/prod" \
  "trixie" \
  "main" \
  "amd64"
$STD apt install -y dotnet-sdk-10.0
msg_ok "Installed .NET SDK 10.0"

PG_VERSION="18" setup_postgresql
PG_DB_NAME="aliasvault" PG_DB_USER="aliasvault" setup_postgresql_db

fetch_and_deploy_gh_release "aliasvault" "aliasvault/aliasvault" "tarball"

# 0.31.0 replaced the Blazor client with a React app in apps/web, and split the
# core build flag --browser into --web / --browser-extension.
msg_info "Building AliasVault Core Libraries"
source "$HOME/.cargo/env"
$STD rustup target add wasm32-unknown-unknown
cd /opt/aliasvault/core
$STD bash build-and-distribute.sh --web
msg_ok "Built AliasVault Core Libraries"

msg_info "Building AliasVault Web Client"
cd /opt/aliasvault/apps/web
$STD npm ci --no-audit --no-fund
$STD npm run build
cp -r /opt/aliasvault/apps/web/dist /opt/aliasvault/www
msg_ok "Built AliasVault Web Client"

msg_info "Building AliasVault Server"
cd /opt/aliasvault/apps/server
$STD dotnet restore aliasvault.sln
$STD dotnet publish AliasVault.Api/AliasVault.Api.csproj -c Release -o /opt/aliasvault/api --no-restore /p:UseAppHost=false
$STD dotnet publish AliasVault.Admin/AliasVault.Admin.csproj -c Release -o /opt/aliasvault/admin --no-restore /p:UseAppHost=false
$STD dotnet publish AliasVault.SmtpService/AliasVault.SmtpService.csproj -c Release -o /opt/aliasvault/smtp --no-restore /p:UseAppHost=false
$STD dotnet publish AliasVault.TaskRunner/AliasVault.TaskRunner.csproj -c Release -o /opt/aliasvault/taskrunner --no-restore /p:UseAppHost=false
$STD dotnet publish Utilities/AliasVault.InstallCli/AliasVault.InstallCli.csproj -c Release -o /opt/aliasvault/installcli --no-restore /p:UseAppHost=false
msg_ok "Built AliasVault Server"

msg_info "Configuring AliasVault"
ADMIN_PASS=$(random_password 16)
# Hashed outside the heredoc so a failing InstallCli aborts instead of writing an empty hash.
ADMIN_HASH=$(dotnet /opt/aliasvault/installcli/AliasVault.InstallCli.dll hash-password "$ADMIN_PASS")
# Secrets with ';' are quoted so the file works as systemd EnvironmentFile and when sourced by bash.
cat <<EOF >/opt/aliasvault/.env
ConnectionStrings__AliasServerDbContext="Host=localhost;Port=5432;Database=aliasvault;Username=aliasvault;Password=${PG_DB_PASS};Maximum Pool Size=80;Minimum Pool Size=5"
JWT_KEY="$(openssl rand -base64 32)"
DATA_PROTECTION_CERT_PASS="$(openssl rand -base64 32)"
ABUSE_METRICS_SALT="$(openssl rand -hex 32)"
ADMIN_PASSWORD_HASH="${ADMIN_HASH}"
ADMIN_PASSWORD_GENERATED="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
HOSTNAME="${LOCAL_IP}"
FORCE_HTTPS_REDIRECT=true
TRUSTED_PROXIES=
ADMIN_IP_ALLOWLIST=
MAX_UPLOAD_SIZE_MB=100
PUBLIC_REGISTRATION_ENABLED=true
SUPPORT_EMAIL=
TERMS_URL=
PRIVATE_EMAIL_DOMAINS=
HIDDEN_PRIVATE_EMAIL_DOMAINS=
SMTP_ADVERTISED_HOSTNAME=
SMTP_TLS_ENABLED=false
IP_LOGGING_ENABLED=true
Logging__LogLevel__Default=Error
Logging__LogLevel__Microsoft__Hosting__Lifetime=Error
Logging__LogLevel__Microsoft=Error
EOF
chmod 600 /opt/aliasvault/.env
mkdir -p /opt/certificates/app
cat <<EOF >~/aliasvault.creds
AliasVault Admin
  URL:      https://${LOCAL_IP}/admin
  Username: admin
  Password: ${ADMIN_PASS}
EOF
chmod 600 ~/aliasvault.creds
msg_ok "Configured AliasVault"

msg_info "Configuring Nginx"
# Renders nginx.conf on every nginx start/reload from the upstream templates
# (apps/server/nginx-443.conf, nginx-80-443.conf) with the upstream
# apps/server/entrypoint.sh, so TRUSTED_PROXIES, FORCE_HTTPS_REDIRECT,
# ADMIN_IP_ALLOWLIST, MAX_UPLOAD_SIZE_MB and HOSTNAME in .env behave as in Docker.
cat <<'EOF' >/usr/local/bin/aliasvault-configure
#!/usr/bin/env bash
set -euo pipefail
set -a
source /opt/aliasvault/.env
set +a
export LETSENCRYPT_ENABLED=false

tmp=$(mktemp)
jq --arg reg "${PUBLIC_REGISTRATION_ENABLED:-true}" \
  --arg mail "${SUPPORT_EMAIL:-}" \
  --arg terms "${TERMS_URL:-}" \
  --arg mode "${DEPLOYMENT_MODE:-}" \
  'del(.ApiUrl) | .PublicRegistrationEnabled=$reg | .SupportEmail=$mail | .TermsUrl=$terms | .DeploymentMode=$mode' \
  /opt/aliasvault/www/appsettings.json >"$tmp"
install -m 644 "$tmp" /opt/aliasvault/www/appsettings.json
rm -f "$tmp"

cp /opt/aliasvault/apps/server/nginx-443.conf /etc/nginx/nginx-443.conf
cp /opt/aliasvault/apps/server/nginx-80-443.conf /etc/nginx/nginx-80-443.conf
sed -n '1,/^# Start nginx and check/p' /opt/aliasvault/apps/server/entrypoint.sh >/run/aliasvault-entrypoint.sh
sh /run/aliasvault-entrypoint.sh
rm -f /run/aliasvault-entrypoint.sh

sed -i \
  -e 's|server client:3000|server 127.0.0.1:3000|' \
  -e 's|server api:3001|server 127.0.0.1:3001|' \
  -e 's|server admin:3002|server 127.0.0.1:3002|' \
  -e 's|root /usr/share/nginx/html;|root /opt/aliasvault/apps/server;|' \
  -e 's|^\(\s*\)include /etc/nginx/mime.types;|&\n\1types { application/javascript mjs; }\n\1include /etc/nginx/aliasvault-client.conf;|' \
  /etc/nginx/nginx.conf

awk '/^[[:space:]]*server[[:space:]]*\{/ {f=1} f {print; n+=gsub(/\{/,"{"); n-=gsub(/\}/,"}"); if (n==0) exit}' \
  /opt/aliasvault/apps/web/nginx.conf |
  sed -e 's|listen 3000;|listen 127.0.0.1:3000;|' -e 's|root /usr/share/nginx/html;|root /opt/aliasvault/www;|' \
    >/etc/nginx/aliasvault-client.conf
EOF
chmod 755 /usr/local/bin/aliasvault-configure
mkdir -p /etc/systemd/system/nginx.service.d
cat <<'EOF' >/etc/systemd/system/nginx.service.d/aliasvault.conf
[Unit]
PartOf=aliasvault.target

[Service]
ExecStartPre=
ExecStartPre=/usr/local/bin/aliasvault-configure
ExecStartPre=/usr/sbin/nginx -t -q -g 'daemon on; master_process on;'
ExecReload=
ExecReload=/usr/local/bin/aliasvault-configure
ExecReload=/usr/sbin/nginx -t -q -g 'daemon on; master_process on;'
ExecReload=/usr/sbin/nginx -g 'daemon on; master_process on;' -s reload
EOF
rm -f /etc/nginx/sites-enabled/default
systemctl daemon-reload
$STD systemctl restart nginx
msg_ok "Configured Nginx"

msg_info "Creating Services"
cat <<EOF >/etc/systemd/system/aliasvault.target
[Unit]
Description=AliasVault
Wants=nginx.service aliasvault-api.service aliasvault-admin.service aliasvault-smtp.service aliasvault-taskrunner.service

[Install]
WantedBy=multi-user.target
EOF
cat <<EOF >/etc/systemd/system/aliasvault-api.service
[Unit]
Description=AliasVault API
After=network.target postgresql.service
Requires=postgresql.service
PartOf=aliasvault.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/aliasvault/api
EnvironmentFile=/opt/aliasvault/.env
Environment=ASPNETCORE_URLS=http://127.0.0.1:3001
Environment=ASPNETCORE_PATHBASE=/api
ExecStart=/usr/bin/dotnet AliasVault.Api.dll
Restart=on-failure
RestartSec=5

[Install]
WantedBy=aliasvault.target
EOF
cat <<EOF >/etc/systemd/system/aliasvault-admin.service
[Unit]
Description=AliasVault Admin
After=network.target aliasvault-api.service
Wants=aliasvault-api.service
PartOf=aliasvault.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/aliasvault/admin
EnvironmentFile=/opt/aliasvault/.env
Environment=ASPNETCORE_URLS=http://127.0.0.1:3002
Environment=ASPNETCORE_PATHBASE=/admin
ExecStart=/usr/bin/dotnet AliasVault.Admin.dll
Restart=on-failure
RestartSec=5

[Install]
WantedBy=aliasvault.target
EOF
cat <<EOF >/etc/systemd/system/aliasvault-smtp.service
[Unit]
Description=AliasVault SMTP Service
After=network.target aliasvault-api.service
Requires=aliasvault-api.service
PartOf=aliasvault.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/aliasvault/smtp
EnvironmentFile=/opt/aliasvault/.env
ExecStart=/usr/bin/dotnet AliasVault.SmtpService.dll
Restart=on-failure
RestartSec=5

[Install]
WantedBy=aliasvault.target
EOF
cat <<EOF >/etc/systemd/system/aliasvault-taskrunner.service
[Unit]
Description=AliasVault Task Runner
After=network.target aliasvault-api.service
Requires=aliasvault-api.service
PartOf=aliasvault.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/aliasvault/taskrunner
EnvironmentFile=/opt/aliasvault/.env
ExecStart=/usr/bin/dotnet AliasVault.TaskRunner.dll
Restart=on-failure
RestartSec=5

[Install]
WantedBy=aliasvault.target
EOF
systemctl enable -q aliasvault-api aliasvault-admin aliasvault-smtp aliasvault-taskrunner
systemctl enable -q --now aliasvault.target
msg_ok "Created Services"

motd_ssh
customize
cleanup_lxc
