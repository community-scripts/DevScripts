#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://github.com/redmine/redmine

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

PG_VERSION="17" setup_postgresql
PG_DB_NAME="redmine" PG_DB_USER="redmine" PG_DB_CREDS_FILE="/dev/null" setup_postgresql_db

msg_info "Installing Dependencies"
$STD apt install -y \
  libpq-dev \
  imagemagick
msg_ok "Installed Dependencies"

RUBY_INSTALL_RAILS="false" setup_ruby
fetch_and_deploy_gh_tag "redmine" "redmine/redmine"

msg_info "Configuring Redmine"
ADMIN_PASS="${var_admin_pass:-$(random_password)}"
mkdir -p /opt/redmine_data/files
cat <<EOF >/opt/redmine_data/database.yml
production:
  adapter: postgresql
  database: redmine
  host: localhost
  username: redmine
  password: "${PG_DB_PASS}"
  encoding: utf8
EOF
cat <<EOF >/opt/redmine_data/configuration.yml
default:
  attachments_storage_path: /opt/redmine_data/files
EOF
cat <<EOF >/opt/redmine_data/Gemfile.local
gem 'puma'
EOF
cat <<EOF >/opt/redmine_data/.env
REDMINE_ADMIN_USER=admin
REDMINE_ADMIN_PASS=${ADMIN_PASS}
EOF
chmod 600 /opt/redmine_data/.env /opt/redmine_data/database.yml
ln -sf /opt/redmine_data/database.yml /opt/redmine/config/database.yml
ln -sf /opt/redmine_data/configuration.yml /opt/redmine/config/configuration.yml
ln -sf /opt/redmine_data/Gemfile.local /opt/redmine/Gemfile.local
msg_ok "Configured Redmine"

msg_info "Installing Redmine Gems"
cd /opt/redmine
export PATH="/root/.rbenv/shims:/root/.rbenv/bin:$PATH"
$STD bundle config set --local without 'development test'
$STD bundle install
msg_ok "Installed Redmine Gems"

msg_info "Setting up Redmine"
$STD bundle exec rake generate_secret_token
mv config/initializers/secret_token.rb /opt/redmine_data/secret_token.rb
chmod 600 /opt/redmine_data/secret_token.rb
ln -sf /opt/redmine_data/secret_token.rb config/initializers/secret_token.rb
RAILS_ENV=production $STD bundle exec rake db:migrate
RAILS_ENV=production REDMINE_LANG=en $STD bundle exec rake redmine:load_default_data
RAILS_ENV=production REDMINE_ADMIN_PASS="$ADMIN_PASS" $STD bundle exec rails runner "u = User.find_by_login('admin'); u.password = u.password_confirmation = ENV['REDMINE_ADMIN_PASS']; u.must_change_passwd = false; u.save!"
RAILS_ENV=production $STD bundle exec rake assets:precompile
msg_ok "Set up Redmine"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/redmine.service
[Unit]
Description=Redmine
After=network.target postgresql.service
Wants=postgresql.service

[Service]
Type=simple
WorkingDirectory=/opt/redmine
Environment=RAILS_ENV=production
Environment=RAILS_LOG_TO_STDOUT=1
Environment=PATH=/root/.rbenv/shims:/root/.rbenv/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
ExecStart=/root/.rbenv/shims/bundle exec puma -e production -b tcp://0.0.0.0:3000
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now redmine
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc
