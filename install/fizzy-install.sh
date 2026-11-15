#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://github.com/basecamp/fizzy

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt install -y \
  git \
  libjemalloc2 \
  libmariadb-dev \
  libvips42t64 \
  pkg-config \
  sqlite3
msg_ok "Installed Dependencies"

fetch_and_deploy_gh_branch "fizzy" "basecamp/fizzy" "main"

RUBY_VERSION="$(cat /opt/fizzy/.ruby-version)" RUBY_INSTALL_RAILS="false" setup_ruby

msg_info "Configuring Fizzy"
mkdir -p /opt/fizzy_data
rm -rf /opt/fizzy/storage
ln -s /opt/fizzy_data /opt/fizzy/storage
cat <<EOF >/opt/fizzy_data/.env
RAILS_ENV=production
BUNDLE_WITHOUT=development:test
SECRET_KEY_BASE=$(random_password 128)
BASE_URL=http://${LOCAL_IP}
DISABLE_SSL=true
WEB_CONCURRENCY=2
JOB_CONCURRENCY=1
EOF
if [[ -n "${var_smtp_host:-}" ]]; then
  cat <<EOF >>/opt/fizzy_data/.env
MAILER_FROM_ADDRESS=${var_mail_from:-fizzy@example.com}
SMTP_ADDRESS=${var_smtp_host}
SMTP_PORT=${var_smtp_port:-587}
SMTP_USERNAME=${var_smtp_user:-}
SMTP_PASSWORD=${var_smtp_pass:-}
SMTP_TLS=$([[ "${var_smtp_port:-587}" == "465" ]] && echo true || echo false)
EOF
fi
msg_ok "Configured Fizzy"

msg_info "Building Fizzy"
cd /opt/fizzy
set -a
source /opt/fizzy_data/.env
set +a
$STD bundle install
$STD bin/rails assets:precompile
$STD bin/rails db:prepare
VAPID_KEYS=$(bundle exec ruby -e 'require "web-push"; k = WebPush.generate_key; puts "VAPID_PRIVATE_KEY=#{k.private_key}", "VAPID_PUBLIC_KEY=#{k.public_key}"')
cat <<EOF >>/opt/fizzy_data/.env
${VAPID_KEYS}
EOF
msg_ok "Built Fizzy"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/fizzy.service
[Unit]
Description=Fizzy
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/fizzy
EnvironmentFile=/opt/fizzy_data/.env
Environment=PATH=/root/.rbenv/shims:/root/.rbenv/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
Environment=LD_PRELOAD=/usr/lib/$(uname -m)-linux-gnu/libjemalloc.so.2
ExecStart=/opt/fizzy/bin/thrust /opt/fizzy/bin/rails server
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now fizzy
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc
