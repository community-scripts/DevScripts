#!/usr/bin/env bash
_CS_DEFAULT_URL="https://raw.githubusercontent.com/community-scripts/DevScripts/main"
_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../core}/core/build.func"
source "$_cs_boot" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/build.func")
# Copyright (c) 2021-2026 community-scripts ORG
# Author: Romualdo Alcantara (romualdoag)
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://github.com/gl-inet/glkvm-cloud

APP="GLKVM Cloud"
var_tags="${var_tags:-kvm;remote-access}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-8}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

export var_rttys_admin_name="${var_rttys_admin_name:-}"
export var_rttys_pass="${var_rttys_pass:-}"
export var_glkvm_access_ip="${var_glkvm_access_ip:-}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/glkvm-cloud ]]; then
    msg_error "No GLKVM Cloud Installation Found!"
    exit
  fi

  if check_for_gh_tag "glkvm-cloud" "gl-inet/glkvm-cloud"; then
    msg_info "Stopping Services"
    systemctl stop glkvm-cloud glkvm-coturn
    msg_ok "Stopped Services"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_tag "glkvm-cloud" "gl-inet/glkvm-cloud"

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

    msg_info "Updating configuration"
    if [[ ! -f /opt/glkvm-cloud-data/database/schema.sql ]]; then
      cp /opt/glkvm-cloud/internal/store/sqlite/schema.sql /opt/glkvm-cloud-data/database/schema.sql
    fi
    source /opt/glkvm-cloud-data/.env
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
    systemctl daemon-reload
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
    msg_ok "Updated configuration"

    msg_info "Starting Services"
    systemctl start glkvm-cloud glkvm-coturn
    msg_ok "Started Services"
    msg_ok "Updated successfully!"
  fi
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW}Access it using the following URL:${CL}"
echo -e "${GATEWAY}${BGN}https://${IP}${CL}"
echo -e "${INFO}${YW}Admin password: RTTYS_PASS in /opt/glkvm-cloud-data/.env${CL}"
