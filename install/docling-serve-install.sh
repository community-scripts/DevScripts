#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://github.com/docling-project/docling-serve

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt install -y \
  libgl1 \
  libglib2.0-0t64 \
  tesseract-ocr \
  tesseract-ocr-deu \
  tesseract-ocr-eng \
  tesseract-ocr-fra \
  tesseract-ocr-osd \
  tesseract-ocr-spa
msg_ok "Installed Dependencies"

PYTHON_VERSION="3.12" setup_uv
check_for_gh_release "docling-serve" "docling-project/docling-serve" "${var_appversion:-}"

msg_info "Installing Docling Serve ${CHECK_UPDATE_RELEASE#v}"
$STD uv venv --python 3.12 /opt/docling-serve/.venv
$STD uv pip install --python /opt/docling-serve/.venv/bin/python --torch-backend cpu "docling-serve[rapidocr,tesserocr]==${CHECK_UPDATE_RELEASE#v}"
cat <<EOF >~/.docling-serve
${CHECK_UPDATE_RELEASE#v}
EOF
msg_ok "Installed Docling Serve ${CHECK_UPDATE_RELEASE#v}"

msg_info "Downloading Docling Models"
$STD /opt/docling-serve/.venv/bin/docling-tools models download -o /opt/docling-serve_data/models layout tableformer picture_classifier rapidocr
msg_ok "Downloaded Docling Models"

msg_info "Configuring Docling Serve"
cat <<EOF >/opt/docling-serve_data/.env
UVICORN_HOST=0.0.0.0
UVICORN_PORT=5001
DOCLING_SERVE_ENABLE_UI=true
DOCLING_SERVE_ARTIFACTS_PATH=/opt/docling-serve_data/models
DOCLING_SERVE_API_KEY=${var_docling_api_key:-$(random_password 32)}
TESSDATA_PREFIX=/usr/share/tesseract-ocr/5/tessdata
EOF
chmod 600 /opt/docling-serve_data/.env
msg_ok "Configured Docling Serve"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/docling-serve.service
[Unit]
Description=Docling Serve
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=/opt/docling-serve_data
EnvironmentFile=/opt/docling-serve_data/.env
ExecStart=/opt/docling-serve/.venv/bin/docling-serve run
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now docling-serve
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc
