#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: stout01
# Co-Author: J0113
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://github.com/BerriAI/litellm

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing LiteLLM Dependencies"
$STD apt install -y libsndfile1 nginx
msg_ok "Installed LiteLLM Dependencies"

NODE_VERSION="24" NODE_COREPACK_ENABLE="0" setup_nodejs
PG_VERSION="17" setup_postgresql
PG_DB_NAME="litellm_db"
PG_DB_USER="litellm"
PG_DB_PASS="$(random_password 32)"
PG_DB_CREDS_FILE="/dev/null" setup_postgresql_db
PYTHON_VERSION="3.13" setup_uv

msg_info "Installing LiteLLM and Generating the Prisma Client"
venv_path="/opt/litellm/.venv"
$STD uv venv --python 3.13 "$venv_path"
$STD uv pip install --python "$venv_path/bin/python" "litellm[proxy,extra-proxy]==${var_litellm_version:?LiteLLM version must be supplied by ct/litellm.sh}" "prisma==${var_litellm_prisma_version:?LiteLLM Prisma version must be supplied by ct/litellm.sh}"
schema_path=$("$venv_path/bin/python" -c 'from importlib.util import find_spec; from pathlib import Path; print(Path(find_spec("litellm").origin).parent / "proxy" / "schema.prisma")')
$STD env "PATH=$venv_path/bin:$PATH" "$venv_path/bin/prisma" generate --schema="$schema_path"
msg_ok "Installed LiteLLM and Generated the Prisma Client"

msg_info "Configuring LiteLLM"
install -m 0600 /dev/null /opt/litellm/.env
cat <<EOF >/opt/litellm/.env
LITELLM_MASTER_KEY=sk-$(random_password 48)
LITELLM_SALT_KEY=sk-$(random_password 48)
DATABASE_URL=postgresql://${PG_DB_USER}:${PG_DB_PASS}@127.0.0.1:5432/${PG_DB_NAME}
EOF
cat <<'EOF' >/opt/litellm/litellm.yaml
model_list: []
general_settings:
  master_key: os.environ/LITELLM_MASTER_KEY
  database_url: os.environ/DATABASE_URL
  store_model_in_db: true
  trusted_proxy_ranges: ["127.0.0.1/32"]
EOF
msg_ok "Configured LiteLLM"

msg_info "Starting LiteLLM"
cat <<'EOF' >/etc/systemd/system/litellm.service
[Unit]
Description=LiteLLM
After=network.target postgresql.service
Requires=postgresql.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/litellm
EnvironmentFile=/opt/litellm/.env
Environment=PATH=/opt/litellm/.venv/bin:/usr/local/bin:/usr/bin:/bin
ExecStart=/opt/litellm/.venv/bin/litellm --config /opt/litellm/litellm.yaml --host 127.0.0.1 --port 4000
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now litellm

deadline=$((SECONDS + 180))
until health=$(curl -fsS --max-time 5 http://127.0.0.1:4000/health/readiness 2>/dev/null) && jq -e '.db == "connected"' <<<"$health" >/dev/null; do
  if ((SECONDS >= deadline)); then
    msg_error "LiteLLM did not become ready with PostgreSQL. Check journalctl -u litellm."
    exit 1
  fi
  sleep 2
done
msg_ok "Started LiteLLM with PostgreSQL"

create_self_signed_cert "litellm"
msg_info "Configuring the LiteLLM Web Proxy"
http_redirect='    if ($scheme = http) { return 301 https://$host$request_uri; }'
if [[ "${var_litellm_http:-yes}" == "yes" ]]; then
  http_redirect=""
fi
cat <<EOF >/etc/nginx/sites-available/litellm
map \$http_upgrade \$litellm_connection_upgrade {
    default upgrade;
    '' close;
}

server {
    listen 80;
    listen 443 ssl;
    server_name _;
    ssl_certificate /etc/ssl/litellm/litellm.crt;
    ssl_certificate_key /etc/ssl/litellm/litellm.key;
    client_max_body_size 0;
${http_redirect}

    location / {
        proxy_pass http://127.0.0.1:4000;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Forwarded-For \$remote_addr;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \$litellm_connection_upgrade;
        proxy_buffering off;
        proxy_read_timeout 600s;
    }
}
EOF
nginx_enable_site "litellm"
msg_ok "Configured the LiteLLM Web Proxy"

motd_ssh
customize
cleanup_lxc
