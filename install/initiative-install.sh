#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Marc Went (Dunky13)
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://github.com/beyonders-studio/initiative

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

if [[ "$(get_os_info id)" != "debian" || "$(get_os_info version)" != "13" ]]; then
  msg_error "Initiative server packages require Debian 13 with Python 3.13."
  exit 1
fi
if [[ -e /etc/initiative/server.env ]]; then
  msg_error "Initiative is already configured. Run update instead of reinstalling."
  exit 1
fi

msg_info "Installing Initiative Dependencies"
$STD apt install -y nginx
msg_ok "Installed Initiative Dependencies"

PG_VERSION="17" USE_PGDG_REPO=false setup_postgresql
# Keep generated credentials out of shell traces and supplementary credentials files.
set +x
umask 0077
PG_DB_PASS=$(random_password 32)
# Startup uses the owner only to provision RLS roles and the LEAKPROOF search operator.
PG_DB_NAME="initiative" PG_DB_USER="initiative" PG_DB_GRANT_SUPERUSER=true PG_DB_CREDS_FILE=/dev/null setup_postgresql_db

release="${var_appversion:-$(get_latest_github_release "beyonders-studio/initiative" false)}"
if [[ ! "$release" =~ ^v?[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  msg_error "Unsupported Initiative release tag: $release"
  exit 1
fi
arch=$(dpkg --print-architecture)
release_dir=$(mktemp -d /opt/initiative-release.XXXXXX)
FORCE_UPDATE=1 USE_ORIGINAL_FILENAME=true fetch_and_deploy_gh_release \
  "initiative-package" "beyonders-studio/initiative" "singlefile" "$release" "$release_dir" \
  "initiative-server_${release#v}-*_${arch}.deb"
FORCE_UPDATE=1 USE_ORIGINAL_FILENAME=true fetch_and_deploy_gh_release \
  "initiative-checksums" "beyonders-studio/initiative" "singlefile" "$release" "$release_dir" \
  "initiative-server-deb-${arch}.sha256"

msg_info "Verifying Initiative Server Package"
(cd "$release_dir" && sha256sum --check --strict "initiative-server-deb-${arch}.sha256")
packages=("$release_dir"/initiative-server_"${release#v}"-*_"${arch}".deb)
if [[ "${#packages[@]}" != 1 || ! -f "${packages[0]}" ]] ||
  [[ "$(dpkg-deb --field "${packages[0]}" Package)" != "initiative-server" ||
  "$(dpkg-deb --field "${packages[0]}" Architecture)" != "$arch" ]]; then
  msg_error "The Initiative release does not contain one matching native server package."
  exit 1
fi
DEBIAN_FRONTEND=noninteractive SYSTEMD_OFFLINE=1 $STD apt install -y "${packages[0]}"
msg_ok "Installed Verified Initiative Server Package"

msg_info "Configuring Initiative"
cat <<EOF >/etc/initiative/server.env
SECRET_KEY=$(openssl rand -hex 32)
DATABASE_URL=postgresql+asyncpg://initiative:${PG_DB_PASS}@127.0.0.1:5432/initiative
APP_URL=https://${LOCAL_IP}
INITIATIVE_HOST=127.0.0.1
INITIATIVE_PORT=8173
BEHIND_PROXY=true
FORWARDED_ALLOW_IPS=127.0.0.1,::1
UPLOADS_DIR=/var/lib/initiative/uploads
ENABLE_PUBLIC_REGISTRATION=false
EOF
chown root:initiative /etc/initiative/server.env
chmod 0640 /etc/initiative/server.env
unset PG_DB_PASS
msg_ok "Configured Initiative"

# Web Crypto and passkeys require a secure browser context on LAN addresses too.
create_self_signed_cert "initiative"
msg_info "Configuring Initiative HTTPS Proxy"
cat <<'EOF' >/etc/nginx/sites-available/initiative
server {
    listen 80;
    listen [::]:80;
    server_name _;
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl;
    listen [::]:443 ssl;
    http2 on;
    server_name _;
    ssl_certificate /etc/ssl/initiative/initiative.crt;
    ssl_certificate_key /etc/ssl/initiative/initiative.key;
    client_max_body_size 100m;

    location / {
        proxy_pass http://127.0.0.1:8173;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $remote_addr;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_read_timeout 3600s;
        proxy_buffering off;
    }
}
EOF
nginx_enable_site "initiative"
# SYSTEMD_OFFLINE also skips the package hook's unit reload.
systemctl daemon-reload
systemctl enable -q --now nginx initiative-server
msg_ok "Configured Initiative HTTPS Proxy"

msg_info "Checking Initiative Readiness"
if ! $STD curl --fail-with-body --silent --retry 90 --retry-delay 2 \
  --retry-connrefused --retry-all-errors --retry-max-time 180 --max-time 5 \
  --output "$release_dir/ready.json" http://127.0.0.1:8173/api/v1/readyz; then
  msg_error "Initiative readiness request failed. Inspect $release_dir/ready.json and journalctl -u initiative-server."
  exit 1
fi
if ! readiness_status=$(jq -ers '
  select(length == 1) | .[0]
  | select(type == "object")
  | select(.checks | type == "object")
  | select(
      (.status == "ok" or .status == "degraded")
      and .checks.database == "ok"
      and .checks.database_system == "ok"
      and .checks.database_provisioning == "ok"
      and (.checks | all(. == "ok" or . == "error"))
      and (if .status == "ok" then (.checks | all(. == "ok"))
           else (.checks | any(. == "error")) end)
    )
  | .status
' "$release_dir/ready.json"); then
  msg_error "Initiative returned an invalid or unavailable readiness response. Inspect $release_dir/ready.json."
  exit 1
fi
degraded_checks=$(jq -r '.checks | to_entries | map(select(.value != "ok") | .key) | join(", ")' "$release_dir/ready.json")
cat <<EOF >"${HOME}/.initiative"
${release#v}
EOF
rm -rf "$release_dir"
msg_ok "Initiative Is Ready"
if [[ "$readiness_status" == "degraded" ]]; then
  msg_warn "Initiative is serving with degraded dependencies: $degraded_checks. Inspect journalctl -u initiative-server."
fi

motd_ssh
customize
cleanup_lxc
