#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: andy-vdg
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://hindsight.vectorize.io/

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

PG_VERSION="18" PG_MODULES="pgvector" setup_postgresql
PG_DB_NAME="hindsight" PG_DB_USER="hindsight" PG_DB_EXTENSIONS="vector,pg_trgm,btree_gin" setup_postgresql_db
fetch_and_deploy_gh_release "hindsight" "vectorize-io/hindsight" "tarball"
PYTHON_VERSION="3.11" UV_PROJECT_DIR="/opt/hindsight" setup_uv

msg_info "Setting up Python Environment"
cd /opt/hindsight
$STD uv sync --locked --package hindsight-api-slim --extra local-ml
msg_ok "Set up Python Environment"

msg_info "Downloading Embedding and Reranker Models"
mkdir -p /opt/hindsight_data
HOME=/opt/hindsight_data $STD /opt/hindsight/.venv/bin/python -c "from sentence_transformers import SentenceTransformer, CrossEncoder; SentenceTransformer('BAAI/bge-small-en-v1.5'); CrossEncoder('cross-encoder/ms-marco-MiniLM-L-6-v2')"
msg_ok "Downloaded Embedding and Reranker Models"

msg_info "Configuring Hindsight"
API_KEY=$(random_password 48)
cat <<EOF >/opt/hindsight.env
HINDSIGHT_API_HOST=0.0.0.0
HINDSIGHT_API_PORT=8888
HINDSIGHT_API_DATABASE_URL=postgresql://${PG_DB_USER}:${PG_DB_PASS}@127.0.0.1:5432/${PG_DB_NAME}
HINDSIGHT_API_TENANT_EXTENSION=hindsight_api.extensions.builtin.tenant:ApiKeyTenantExtension
HINDSIGHT_API_TENANT_API_KEY=${API_KEY}
HINDSIGHT_API_LLM_PROVIDER=${var_llm_provider:-none}
HINDSIGHT_API_LLM_API_KEY=${var_llm_api_key:-}
HINDSIGHT_API_LLM_MODEL=${var_llm_model:-}
HINDSIGHT_API_LLM_BASE_URL=${var_llm_base_url:-}
TRANSFORMERS_VERBOSITY=error
HF_HUB_VERBOSITY=error
TOKENIZERS_PARALLELISM=false
EOF
sed -i '/=$/d' /opt/hindsight.env
chmod 600 /opt/hindsight.env
cat <<EOF >>~/hindsight.creds

Hindsight API Key: ${API_KEY}
EOF
chmod 600 ~/hindsight.creds
msg_ok "Configured Hindsight"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/hindsight.service
[Unit]
Description=Hindsight API
Wants=network-online.target
After=network-online.target postgresql.service
Requires=postgresql.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/hindsight_data
Environment=HOME=/opt/hindsight_data
Environment=PYTHONUNBUFFERED=1
EnvironmentFile=/opt/hindsight.env
ExecStart=/opt/hindsight/.venv/bin/hindsight-api
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now hindsight
msg_ok "Created Service"

if [[ -z "${var_llm_provider:-}" ]]; then
  msg_warn "No LLM configured: Hindsight stores plain chunks only. Set HINDSIGHT_API_LLM_PROVIDER and its key in /opt/hindsight.env, then run systemctl restart hindsight"
fi

motd_ssh
customize
cleanup_lxc
