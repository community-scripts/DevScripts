#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Romualdo Alcantara (romualdoag)
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://github.com/gl-inet/glkvm-cloud

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt install -y \
  build-essential \
  ca-certificates \
  coturn \
  curl \
  git \
  openssl \
  python3 \
  sqlite3
msg_ok "Installed Dependencies"

fetch_and_deploy_gh_tag "glkvm-cloud" "gl-inet/glkvm-cloud"

GO_VERSION="$(grep -m1 '^go ' /opt/glkvm-cloud/go.mod | awk '{print $2}')" setup_go
NODE_VERSION="24" NODE_MODULE="yarn" setup_nodejs

msg_info "Building GLKVM Cloud interface"
cd /opt/glkvm-cloud/ui
$STD yarn install --frozen-lockfile
$STD yarn build
msg_ok "Built GLKVM Cloud interface"

msg_info "Building GLKVM Cloud service"
cd /opt/glkvm-cloud
CGO_ENABLED=0 $STD go build -ldflags "-s -w" -o /opt/glkvm-cloud/rttys ./cmd/glkvm-cloud
rm -rf /opt/glkvm-cloud/ui/node_modules
$STD go clean -cache -modcache
msg_ok "Built GLKVM Cloud service"

msg_info "Configuring GLKVM Cloud"
mkdir -p /opt/glkvm-cloud-data/database /opt/glkvm-cloud-data/certificate
if [[ ! -f /opt/glkvm-cloud-data/database/schema.sql ]]; then
  cp /opt/glkvm-cloud/internal/store/sqlite/schema.sql /opt/glkvm-cloud-data/database/schema.sql
fi
var_rttys_admin_name="${var_rttys_admin_name:-admin}"
var_rttys_pass="${var_rttys_pass:-$(random_password 32)}"
var_glkvm_access_ip="${var_glkvm_access_ip:-$(curl -fsS --max-time 5 https://api.ipify.org 2>/dev/null || echo "$LOCAL_IP")}"
cat <<EOF >/opt/glkvm-cloud-data/.env
GLKVM_ACCESS_IP=${var_glkvm_access_ip}
RTTYS_TOKEN=$(random_password 32)
RTTYS_PASS=${var_rttys_pass}
RTTYS_ADMIN_NAME=${var_rttys_admin_name}
RTTYS_DEVICE_PORT=5912
RTTYS_DEVICE_MTLS_PORT=5915
RTTYS_LEGACY_TOKEN_ACCESS=true
RTTYS_WEBUI_PORT=443
RTTYS_HTTP_PROXY_PORT=10443
TURN_PORT=3478
TURN_USER=$(random_password 16)
TURN_PASS=$(random_password 32)
REVERSE_PROXY_ENABLED=false
DEVICE_ACCESS_HOST=
SELFHOST_WEBUI_URL=
DEVICE_ENDPOINT_HOST=
WEB_UI_HOST=
LDAP_ENABLED=false
LDAP_SERVER=
LDAP_PORT=389
LDAP_USE_TLS=false
LDAP_BIND_DN=
LDAP_BIND_PASSWORD=
LDAP_BASE_DN=
LDAP_USER_FILTER="(uid=%s)"
LDAP_ALLOWED_GROUPS=
LDAP_ALLOWED_USERS=
LDAP_ADMIN_GROUP=
LDAP_ADMIN_USERS=
OIDC_ENABLED=false
OIDC_PRIMARY_LOGIN=false
OIDC_ISSUER=
OIDC_CLIENT_ID=
OIDC_CLIENT_SECRET=
OIDC_AUTH_URL=
OIDC_TOKEN_URL=
OIDC_REDIRECT_URL=
OIDC_SCOPES="openid profile email"
OIDC_ALLOWED_USERS=
OIDC_ALLOWED_SUBS=
OIDC_ALLOWED_USERNAMES=
OIDC_ALLOWED_GROUPS=
OIDC_ADMIN_GROUP=
OIDC_ADMIN_USERS=
EOF
chmod 600 /opt/glkvm-cloud-data/.env
source /opt/glkvm-cloud-data/.env
cat <<EOF >/opt/glkvm-cloud-data/rttys.conf
token: ${RTTYS_TOKEN}
password: ${RTTYS_PASS}
admin-name: ${RTTYS_ADMIN_NAME}
webrtc-ip: ${GLKVM_ACCESS_IP}
webrtc-port: ${TURN_PORT}
webrtc-username: ${TURN_USER}
webrtc-password: ${TURN_PASS}
addr-dev: :${RTTYS_DEVICE_PORT}
addr-dev-mtls: :${RTTYS_DEVICE_MTLS_PORT}
legacy-token-access: ${RTTYS_LEGACY_TOKEN_ACCESS}
addr-user: :${RTTYS_WEBUI_PORT}
addr-http-proxy: :${RTTYS_HTTP_PROXY_PORT}
ldap-enabled: ${LDAP_ENABLED}
ldap-server: ${LDAP_SERVER}
ldap-port: ${LDAP_PORT}
ldap-use-tls: ${LDAP_USE_TLS}
ldap-bind-dn: ${LDAP_BIND_DN}
ldap-base-dn: ${LDAP_BASE_DN}
ldap-user-filter: ${LDAP_USER_FILTER}
ldap-allowed-groups: ${LDAP_ALLOWED_GROUPS}
ldap-allowed-users: ${LDAP_ALLOWED_USERS}
ldap-admin-group: ${LDAP_ADMIN_GROUP}
ldap-admin-users: ${LDAP_ADMIN_USERS}
oidc-enabled: ${OIDC_ENABLED}
oidc-primary-login: ${OIDC_PRIMARY_LOGIN}
oidc-generic-issuer: ${OIDC_ISSUER}
oidc-generic-client-id: ${OIDC_CLIENT_ID}
oidc-generic-auth-url: ${OIDC_AUTH_URL}
oidc-generic-token-url: ${OIDC_TOKEN_URL}
oidc-generic-redirect-url: ${OIDC_REDIRECT_URL}
oidc-generic-scopes: ${OIDC_SCOPES}
oidc-generic-allowed-users: ${OIDC_ALLOWED_USERS}
oidc-generic-allowed-subs: ${OIDC_ALLOWED_SUBS}
oidc-generic-allowed-usernames: ${OIDC_ALLOWED_USERNAMES}
oidc-generic-allowed-groups: ${OIDC_ALLOWED_GROUPS}
oidc-admin-group: ${OIDC_ADMIN_GROUP}
oidc-admin-users: ${OIDC_ADMIN_USERS}
selfhost-webui-url: ${SELFHOST_WEBUI_URL}
device-access-host: ${DEVICE_ACCESS_HOST}
EOF
cat <<EOF >/opt/glkvm-cloud-data/turnserver.conf
listening-port=${TURN_PORT}
lt-cred-mech
user=${TURN_USER}:${TURN_PASS}
realm=glkvm
no-multicast-peers
external-ip=${GLKVM_ACCESS_IP}
EOF
ln -sfn /opt/glkvm-cloud-data/database /home/database
ln -sfn /opt/glkvm-cloud-data/certificate /home/certificate
msg_ok "Configured GLKVM Cloud"

msg_info "Creating Services"
cat <<EOF >/etc/systemd/system/glkvm-cloud.service
[Unit]
Description=GLKVM Cloud
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/glkvm-cloud
Environment=RTTYS_CONF=/opt/glkvm-cloud-data/rttys.conf
EnvironmentFile=/opt/glkvm-cloud-data/.env
ExecStart=/opt/glkvm-cloud/rttys
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
cat <<EOF >/etc/systemd/system/glkvm-coturn.service
[Unit]
Description=GLKVM Cloud TURN server
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/bin/turnserver -c /opt/glkvm-cloud-data/turnserver.conf
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now glkvm-cloud glkvm-coturn
msg_ok "Created Services"

msg_info "Verifying GLKVM Cloud"
sleep 8
if [[ "$(systemctl show glkvm-cloud -p SubState --value)" != "running" ]]; then
  journalctl -u glkvm-cloud --no-pager -n 10 >&2 || true
  msg_error "GLKVM Cloud failed to start"
  exit 1
fi
if [[ "$(systemctl show glkvm-coturn -p SubState --value)" != "running" ]]; then
  journalctl -u glkvm-coturn --no-pager -n 10 >&2 || true
  msg_error "GLKVM TURN server failed to start"
  exit 1
fi
msg_ok "Verified GLKVM Cloud"

motd_ssh
customize
cleanup_lxc
