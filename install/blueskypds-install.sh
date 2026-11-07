#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Community Scripts contributor
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://github.com/bluesky-social/pds

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

if [[ -z "${var_pds_hostname:-}" ]]; then
  read -r -p "${TAB3}Public PDS domain (for example example.com): " var_pds_hostname
fi
var_pds_hostname="$(printf '%s' "$var_pds_hostname" | tr '[:upper:]' '[:lower:]')"
if [[ ! "$var_pds_hostname" =~ ^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,}$ ]]; then
  msg_error "Invalid Bluesky PDS domain. Use a public DNS name such as example.com."
  exit 1
fi

if [[ -z "${var_admin_email:-}" ]]; then
  read -r -p "${TAB3}Email address for Caddy/Let's Encrypt: " var_admin_email
fi
if [[ ! "$var_admin_email" =~ ^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$ ]]; then
  msg_error "Invalid email address."
  exit 1
fi

msg_info "Installing Bluesky PDS build dependencies"
$STD apt install -y build-essential ca-certificates curl git gpg apt-transport-https libsqlite3-dev libvips-dev openssl pkg-config python3 sqlite3 xxd debian-keyring debian-archive-keyring
msg_ok "Installed Bluesky PDS build dependencies"

NODE_VERSION="24" setup_nodejs
$STD npm install --global pnpm@12.16.1
export PUPPETEER_SKIP_DOWNLOAD=true
fetch_and_deploy_gh_branch "bluesky-pds" "bluesky-social/atproto" "main"
cd /opt/bluesky-pds

msg_info "Building Bluesky PDS from source"
$STD pnpm install --frozen-lockfile --filter 'pds-service...' --shamefully-hoist
$STD pnpm run --recursive --stream --workspace-concurrency 1 --filter 'pds-service...' build --force
$STD pnpm install --prod --filter 'pds-service...' --shamefully-hoist --frozen-lockfile --prefer-offline --config.confirmModulesPurge=false
msg_ok "Built Bluesky PDS"

fetch_and_deploy_gh_release "goat" "bluesky-social/goat" "binary"

msg_info "Installing Caddy"
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor --yes -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list >/dev/null
chmod o+r /usr/share/keyrings/caddy-stable-archive-keyring.gpg /etc/apt/sources.list.d/caddy-stable.list
$STD apt update
$STD apt install -y caddy
msg_ok "Installed Caddy"

msg_info "Creating Bluesky PDS data directory"
install -d -m 0700 /opt/bluesky-pds_data
PDS_ADMIN_PASSWORD="$(openssl rand -hex 24)"
PDS_JWT_SECRET="$(openssl rand -hex 32)"
PDS_PLC_ROTATION_KEY_K256_PRIVATE_KEY_HEX="$(openssl ecparam --name secp256k1 --genkey --noout --outform DER | tail --bytes=+8 | head --bytes=32 | xxd --plain --cols 32)"
cat <<PDS_CONFIG >/opt/bluesky-pds_data/pds.env
PDS_HOSTNAME=${var_pds_hostname}
PDS_JWT_SECRET=${PDS_JWT_SECRET}
PDS_ADMIN_PASSWORD=${PDS_ADMIN_PASSWORD}
PDS_PLC_ROTATION_KEY_K256_PRIVATE_KEY_HEX=${PDS_PLC_ROTATION_KEY_K256_PRIVATE_KEY_HEX}
PDS_DATA_DIRECTORY=/opt/bluesky-pds_data
PDS_BLOBSTORE_DISK_LOCATION=/opt/bluesky-pds_data/blocks
PDS_BLOB_UPLOAD_LIMIT=314572800
PDS_DID_PLC_URL=https://plc.directory
PDS_BSKY_APP_VIEW_URL=https://api.bsky.app
PDS_BSKY_APP_VIEW_DID=did:web:api.bsky.app
PDS_REPORT_SERVICE_URL=https://mod.bsky.app
PDS_REPORT_SERVICE_DID=did:plc:ar7c4by46qjdydhdevvrndac
PDS_CRAWLERS=https://bsky.network
LOG_ENABLED=true
PDS_RATE_LIMITS_ENABLED=true
PDS_INVITE_REQUIRED=true
PDS_CONFIG
chmod 0600 /opt/bluesky-pds_data/pds.env
msg_ok "Created Bluesky PDS configuration and secrets"

msg_info "Creating Bluesky PDS systemd service"
cat <<'SYSTEMD_UNIT' >/etc/systemd/system/pds.service
[Unit]
Description=Bluesky Personal Data Server
Documentation=https://github.com/bluesky-social/pds
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
WorkingDirectory=/opt/bluesky-pds/services/pds
Environment=NODE_ENV=production
Environment=PDS_PORT=3000
Environment=UV_USE_IO_URING=0
EnvironmentFile=/opt/bluesky-pds_data/pds.env
ExecStart=/usr/bin/node --heapsnapshot-signal=SIGUSR2 --enable-source-maps --import=@atproto/pds/telemetry index.ts
Restart=on-failure
RestartSec=5
TimeoutStopSec=30
LimitNOFILE=65536
NoNewPrivileges=yes
PrivateTmp=yes
ProtectSystem=strict
ProtectHome=yes
ReadWritePaths=/opt/bluesky-pds_data

[Install]
WantedBy=multi-user.target
SYSTEMD_UNIT
systemctl daemon-reload
systemctl enable -q --now pds
msg_ok "Created Bluesky PDS systemd service"

msg_info "Configuring Caddy HTTPS"
cat <<CADDYFILE >/etc/caddy/Caddyfile
{
  email ${var_admin_email}
  on_demand_tls {
    ask http://127.0.0.1:3000/tls-check
  }
}

${var_pds_hostname}, *.${var_pds_hostname} {
  tls {
    on_demand
  }
  reverse_proxy http://127.0.0.1:3000
}
CADDYFILE
install -d -m 0755 /etc/systemd/system/caddy.service.d
cat <<'CADDY_OVERRIDE' >/etc/systemd/system/caddy.service.d/pds.conf
[Service]
Environment=GODEBUG=multipathtcp=0
CADDY_OVERRIDE
systemctl daemon-reload
systemctl enable -q caddy
systemctl restart caddy
msg_ok "Configured Caddy HTTPS reverse proxy"

msg_info "Installing native Bluesky PDS administration command"
cat <<'PDSADMIN' >/usr/local/bin/pdsadmin
#!/usr/bin/env bash
set -Eeuo pipefail
set -a
source /opt/bluesky-pds_data/pds.env
set +a
export PDS_HOST="http://127.0.0.1:3000"
exec goat pds admin "$@"
PDSADMIN
chmod 0755 /usr/local/bin/pdsadmin
msg_ok "Installed pdsadmin command"

for attempt in {1..30}; do
  if curl -fsS http://127.0.0.1:3000/xrpc/_health >/dev/null; then
    break
  fi
  sleep 2
done
if ! curl -fsS http://127.0.0.1:3000/xrpc/_health >/dev/null; then
  msg_error "Bluesky PDS did not become healthy. Check: journalctl -u pds -n 100 --no-pager"
  exit 1
fi

motd_ssh
customize
cleanup_lxc

msg_ok "Bluesky PDS installation completed"
echo -e "${INFO}${YW}PDS URL:${CL} ${BGN}https://${var_pds_hostname}${CL}"
echo -e "${INFO}${YW}Health check:${CL} ${GN}https://${var_pds_hostname}/xrpc/_health${CL}"
echo -e "${INFO}${YW}PDS administration:${CL} ${GN}pdsadmin help${CL}"
echo -e "${INFO}${YW}Create an account:${CL} ${GN}pdsadmin account create --handle HANDLE.${var_pds_hostname} --email EMAIL --password PASSWORD${CL}"
echo -e "${INFO}${YW}Admin password is stored in:${CL} ${GN}/opt/bluesky-pds_data/pds.env${CL}"
echo -e "${INFO}${YW}Logs:${CL} ${GN}journalctl -u pds -f${CL}"
echo -e "${INFO}${YW}Required DNS:${CL} ${GN}A ${var_pds_hostname} and A *.${var_pds_hostname} pointing to this LXC${CL}"
echo -e "${INFO}${YW}Required inbound ports:${CL} ${GN}TCP 80 and 443${CL}"
