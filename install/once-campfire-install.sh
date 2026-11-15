#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://github.com/basecamp/once-campfire

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
  pkg-config \
  libvips42t64 \
  redis-server
msg_ok "Installed Dependencies"

setup_ffmpeg
fetch_and_deploy_gh_release "once-campfire" "basecamp/once-campfire" "tarball"
RUBY_VERSION="$(cat /opt/once-campfire/.ruby-version)" RUBY_INSTALL_RAILS="false" HOME=/root setup_ruby

msg_info "Building Campfire"
mkdir -p /opt/once-campfire_data/storage
ln -sfn /opt/once-campfire_data/storage /opt/once-campfire/storage
cd /opt/once-campfire
$STD bundle config set --local deployment true
$STD bundle config set --local without "development test"
$STD bundle install
rm -rf vendor/bundle/ruby/*/cache vendor/bundle/ruby/*/bundler/gems/*/.git
RAILS_ENV=production SECRET_KEY_BASE_DUMMY=1 $STD bin/rails assets:precompile
msg_ok "Built Campfire"

msg_info "Configuring Campfire"
cat <<EOF >/opt/once-campfire_data/.env
RAILS_ENV=production
DISABLE_SSL=true
SKIP_TELEMETRY=true
REDIS_URL=redis://127.0.0.1:6379
HTTP_PORT=80
HTTP_IDLE_TIMEOUT=60
HTTP_READ_TIMEOUT=300
HTTP_WRITE_TIMEOUT=300
EOF
bundle exec ruby script/admin/generate-secrets >>/opt/once-campfire_data/.env
chmod 600 /opt/once-campfire_data/.env
msg_ok "Configured Campfire"

msg_info "Creating Services"
cat <<EOF >/etc/systemd/system/once-campfire.service
[Unit]
Description=Campfire
After=network-online.target redis-server.service
Wants=network-online.target redis-server.service

[Service]
Type=simple
WorkingDirectory=/opt/once-campfire
EnvironmentFile=/opt/once-campfire_data/.env
Environment=HOME=/root
Environment=PATH=/root/.rbenv/shims:/root/.rbenv/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
ExecStart=/root/.rbenv/shims/bundle exec thrust bin/start-app
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
cat <<EOF >/etc/systemd/system/once-campfire-workers.service
[Unit]
Description=Campfire Workers
After=network-online.target redis-server.service
Wants=network-online.target redis-server.service

[Service]
Type=simple
WorkingDirectory=/opt/once-campfire
EnvironmentFile=/opt/once-campfire_data/.env
Environment=HOME=/root
Environment=PATH=/root/.rbenv/shims:/root/.rbenv/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
Environment=FORK_PER_JOB=false
Environment=INTERVAL=0.1
ExecStart=/root/.rbenv/shims/bundle exec resque-pool
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now redis-server once-campfire once-campfire-workers
msg_ok "Created Services"

motd_ssh
customize
cleanup_lxc
