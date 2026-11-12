#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://github.com/flipt-io/flipt

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt install -y nginx
msg_ok "Installed Dependencies"

fetch_and_deploy_gh_release "flipt" "flipt-io/flipt" "prebuild" "latest" "/opt/flipt" "flipt_linux_$(arch_resolve "x86_64" "arm64").tar.gz"

msg_info "Configuring Flipt"
ADMIN_PASS="${var_admin_pass:-$(random_password)}"
API_TOKEN="${var_api_key:-$(random_password 32)}"
mkdir -p /opt/flipt_data
cat <<EOF >/opt/flipt_data/.env
ADMIN_USER=admin
ADMIN_PASSWORD=${ADMIN_PASS}
API_TOKEN=${API_TOKEN}
EOF
chmod 600 /opt/flipt_data/.env
cat <<'EOF' >/opt/flipt_data/config.yml
version: "2.0"
meta:
  state_directory: /opt/flipt_data/state
  telemetry_enabled: false
server:
  http_port: 8081
storage:
  default:
    backend:
      type: local
      path: /opt/flipt_data/repo
authentication:
  required: true
  methods:
    token:
      enabled: true
      storage:
        tokens:
          admin:
            credential: ${env:API_TOKEN}
            metadata:
              name: admin
EOF
msg_ok "Configured Flipt"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/flipt.service
[Unit]
Description=Flipt
After=network.target

[Service]
Type=simple
WorkingDirectory=/opt/flipt_data
EnvironmentFile=/opt/flipt_data/.env
ExecStart=/opt/flipt/flipt server --config /opt/flipt_data/config.yml
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now flipt
msg_ok "Created Service"

msg_info "Configuring Nginx"
cat <<EOF >/etc/nginx/flipt.htpasswd
admin:$(openssl passwd -6 "$ADMIN_PASS")
EOF
chown root:www-data /etc/nginx/flipt.htpasswd
chmod 640 /etc/nginx/flipt.htpasswd
cat <<EOF >/etc/nginx/sites-available/flipt
# Browsers log in with basic auth and get the API token injected; API clients send the token themselves
map \$http_authorization \$flipt_realm {
    ~*^bearer\s off;
    default     "Flipt";
}

map \$http_authorization \$flipt_authorization {
    ~*^bearer\s \$http_authorization;
    default     "Bearer ${API_TOKEN}";
}

server {
    listen 8080;
    server_name _;

    location / {
        auth_basic \$flipt_realm;
        auth_basic_user_file /etc/nginx/flipt.htpasswd;
        proxy_pass http://127.0.0.1:8081;
        proxy_http_version 1.1;
        proxy_buffering off;
        proxy_read_timeout 1h;
        proxy_set_header Authorization \$flipt_authorization;
        proxy_set_header Host \$host;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }
}
EOF
chmod 600 /etc/nginx/sites-available/flipt
nginx_enable_site "flipt"
msg_ok "Configured Nginx"

motd_ssh
customize
cleanup_lxc
