#!/usr/bin/env bash
# Copyright (c) 2021-2026 community-scripts ORG
# Author: Jayme Snyder (jaymemaurice)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://www.nautobot.com/ | https://github.com/nautobot/nautobot

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt install -y \
  nginx \
  redis-server \
  git \
  build-essential \
  libxml2-dev \
  libxslt1-dev \
  libffi-dev \
  libpq-dev \
  libssl-dev \
  libpcre2-dev \
  zlib1g-dev \
  python3 \
  python3-pip \
  python3-venv \
  python3-dev \
  openssl
systemctl enable -q --now redis-server
msg_ok "Installed Dependencies"

PG_VERSION="16" setup_postgresql
PG_DB_NAME="nautobot" PG_DB_USER="nautobot" setup_postgresql_db

msg_info "Creating Nautobot Python Environment"
# Nautobot upstream explicitly requires a dedicated `nautobot` system account
# to own the application files and run its web/background services.
useradd --system --user-group --shell /bin/bash --create-home --home-dir /opt/nautobot nautobot
python3 -m venv /opt/nautobot
chown -R nautobot:nautobot /opt/nautobot
$STD runuser -u nautobot -- /opt/nautobot/bin/pip install --upgrade pip wheel
msg_ok "Created Nautobot Python Environment"

msg_info "Installing Nautobot"
# pyuwsgi is intentionally built locally per Nautobot's installation guidance.
# Stay on Nautobot 3.x automatically; a future major upgrade should be deliberate.
$STD runuser -u nautobot -- /opt/nautobot/bin/pip install --upgrade --no-binary=pyuwsgi 'nautobot>=3.2,<4'
msg_ok "Installed Nautobot"

msg_info "Initializing Nautobot Configuration"
# Nautobot's init command otherwise prompts for installation-metrics consent,
# which cannot be answered by an unattended Community Scripts build.
$STD runuser -u nautobot -- env \
  HOME=/opt/nautobot \
  NAUTOBOT_ROOT=/opt/nautobot \
  NAUTOBOT_INSTALLATION_METRICS_ENABLED=False \
  /opt/nautobot/bin/nautobot-server init --disable-installation-metrics
msg_ok "Initialized Nautobot Configuration"

touch /opt/nautobot/local_requirements.txt
chown nautobot:nautobot /opt/nautobot/local_requirements.txt

cat <<EOF >>/opt/nautobot/nautobot_config.py

# -----------------------------------------------------------------------------
# Added by the Community Scripts Nautobot helper.
# Restrict ALLOWED_HOSTS after assigning a permanent hostname/address.
# -----------------------------------------------------------------------------
ALLOWED_HOSTS = ["*"]
INSTALLATION_METRICS_ENABLED = False
DATABASES = {
    "default": {
        "NAME": "${PG_DB_NAME}",
        "USER": "${PG_DB_USER}",
        "PASSWORD": "${PG_DB_PASS}",
        "HOST": "localhost",
        "PORT": "5432",
        "CONN_MAX_AGE": 300,
        "ENGINE": "django.db.backends.postgresql",
    }
}
EOF
chown nautobot:nautobot /opt/nautobot/nautobot_config.py
chmod 640 /opt/nautobot/nautobot_config.py

# Create the media parent explicitly. `install -d` may otherwise create an
# intermediate parent as root, which causes Nautobot's storage health check to
# fail when it creates media/health_check_storage_test.
install -d -m 0755 -o nautobot -g nautobot \
  /opt/nautobot/jobs \
  /opt/nautobot/git \
  /opt/nautobot/media
install -d -m 0755 -o nautobot -g nautobot \
  /opt/nautobot/media/image-attachments \
  /opt/nautobot/media/devicetype-images
chown -R nautobot:nautobot \
  /opt/nautobot/jobs \
  /opt/nautobot/git \
  /opt/nautobot/media

msg_info "Checking Nautobot Media Permissions"
$STD runuser -u nautobot -- bash -c '
  set -e
  test -w /opt/nautobot/media
  probe="/opt/nautobot/media/.install-write-test-$$"
  mkdir "$probe"
  rmdir "$probe"
'
msg_ok "Checked Nautobot Media Permissions"

run_nb() {
  runuser -u nautobot -- env \
    HOME=/opt/nautobot \
    NAUTOBOT_ROOT=/opt/nautobot \
    NAUTOBOT_CONFIG=/opt/nautobot/nautobot_config.py \
    NAUTOBOT_INSTALLATION_METRICS_ENABLED=False \
    "$@"
}

msg_info "Preparing Nautobot Database and Static Files"
$STD run_nb /opt/nautobot/bin/nautobot-server post_upgrade
$STD run_nb /opt/nautobot/bin/nautobot-server check
msg_ok "Prepared Nautobot Database and Static Files"

msg_info "Setting up Nautobot Admin"
DJANGO_USER="Admin"
DJANGO_PASS="$(openssl rand -base64 24 | tr -dc 'a-zA-Z0-9' | cut -c1-16)"
$STD run_nb /opt/nautobot/bin/nautobot-server shell <<EOF
from django.contrib.auth import get_user_model
User = get_user_model()
user, _ = User.objects.get_or_create(username="${DJANGO_USER}")
user.is_superuser = True
user.is_staff = True
user.set_password("${DJANGO_PASS}")
user.save()
EOF

cat <<EOF >/opt/nautobot/.env
NAUTOBOT_ADMIN_USER=${DJANGO_USER}
NAUTOBOT_ADMIN_PASSWORD=${DJANGO_PASS}
NAUTOBOT_DB_NAME=${PG_DB_NAME}
NAUTOBOT_DB_USER=${PG_DB_USER}
NAUTOBOT_DB_PASSWORD=${PG_DB_PASS}
EOF
chown root:root /opt/nautobot/.env
chmod 600 /opt/nautobot/.env
msg_ok "Setup Nautobot Admin"

msg_info "Creating Nautobot Services"
cat <<'EOF' >/opt/nautobot/uwsgi.ini
[uwsgi]
socket = 127.0.0.1:8001
strict = true
master = true
enable-threads = true
vacuum = true
single-interpreter = true
die-on-term = true
need-app = true
disable-logging = true
log-4xx = true
log-5xx = true
http-keepalive = 1
EOF
chown nautobot:nautobot /opt/nautobot/uwsgi.ini
chmod 640 /opt/nautobot/uwsgi.ini

cat <<'EOF' >/etc/systemd/system/nautobot.service
[Unit]
Description=Nautobot WSGI Service
Documentation=https://docs.nautobot.com/projects/core/en/stable/
After=network-online.target postgresql.service redis-server.service
Wants=network-online.target

[Service]
Type=simple
Environment="NAUTOBOT_ROOT=/opt/nautobot"
Environment="NAUTOBOT_CONFIG=/opt/nautobot/nautobot_config.py"
User=nautobot
Group=nautobot
PIDFile=/var/tmp/nautobot.pid
WorkingDirectory=/opt/nautobot
ExecStart=/opt/nautobot/bin/nautobot-server start --pidfile /var/tmp/nautobot.pid --ini /opt/nautobot/uwsgi.ini
ExecStop=/opt/nautobot/bin/nautobot-server start --stop /var/tmp/nautobot.pid
ExecReload=/opt/nautobot/bin/nautobot-server start --reload /var/tmp/nautobot.pid
Restart=on-failure
RestartSec=30
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF

cat <<'EOF' >/etc/systemd/system/nautobot-worker.service
[Unit]
Description=Nautobot Celery Worker
Documentation=https://docs.nautobot.com/projects/core/en/stable/
After=network-online.target postgresql.service redis-server.service
Wants=network-online.target

[Service]
Type=exec
Environment="NAUTOBOT_ROOT=/opt/nautobot"
Environment="NAUTOBOT_CONFIG=/opt/nautobot/nautobot_config.py"
User=nautobot
Group=nautobot
PIDFile=/var/tmp/nautobot-worker.pid
WorkingDirectory=/opt/nautobot
ExecStart=/opt/nautobot/bin/nautobot-server celery worker --loglevel INFO --pidfile /var/tmp/nautobot-worker.pid
Restart=always
RestartSec=30
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF

cat <<'EOF' >/etc/systemd/system/nautobot-scheduler.service
[Unit]
Description=Nautobot Celery Beat Scheduler
Documentation=https://docs.nautobot.com/projects/core/en/stable/
After=network-online.target postgresql.service redis-server.service
Wants=network-online.target

[Service]
Type=exec
Environment="NAUTOBOT_ROOT=/opt/nautobot"
Environment="NAUTOBOT_CONFIG=/opt/nautobot/nautobot_config.py"
User=nautobot
Group=nautobot
PIDFile=/var/tmp/nautobot-scheduler.pid
WorkingDirectory=/opt/nautobot
ExecStart=/opt/nautobot/bin/nautobot-server celery beat --loglevel INFO --pidfile /var/tmp/nautobot-scheduler.pid
Restart=always
RestartSec=30
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now nautobot nautobot-worker nautobot-scheduler
msg_ok "Created Nautobot Services"

msg_info "Configuring NGINX"
$STD openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
  -keyout /etc/ssl/private/nautobot.key \
  -out /etc/ssl/certs/nautobot.crt \
  -subj "/O=Nautobot/OU=Community Scripts/CN=$(hostname -f 2>/dev/null || hostname)"
chmod 600 /etc/ssl/private/nautobot.key

cat <<'EOF' >/etc/nginx/sites-available/nautobot.conf
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    listen 443 ssl default_server;
    listen [::]:443 ssl default_server;
    server_name _;

    ssl_certificate /etc/ssl/certs/nautobot.crt;
    ssl_certificate_key /etc/ssl/private/nautobot.key;

    client_max_body_size 25m;

    location /static/ {
        alias /opt/nautobot/static/;
    }

    location / {
        include uwsgi_params;
        uwsgi_pass 127.0.0.1:8001;
        uwsgi_param Host $host;
        uwsgi_param X-Real-IP $remote_addr;
        uwsgi_param X-Forwarded-For $proxy_add_x_forwarded_for;
        uwsgi_param X-Forwarded-Proto $scheme;
    }
}
EOF
rm -f /etc/nginx/sites-enabled/default
ln -sf /etc/nginx/sites-available/nautobot.conf /etc/nginx/sites-enabled/nautobot.conf
usermod -aG nautobot www-data
chmod 750 /opt/nautobot
$STD nginx -t
systemctl enable -q nginx
systemctl restart nginx
msg_ok "Configured NGINX"

msg_info "Verifying Nautobot"
$STD run_nb /opt/nautobot/bin/nautobot-server health_check
for svc in nautobot nautobot-worker nautobot-scheduler nginx redis-server postgresql; do
  if ! systemctl is-active --quiet "$svc"; then
    msg_error "Service is not active: ${svc}"
    exit 1
  fi
done
msg_ok "Verified Nautobot"

motd_ssh
customize
cleanup_lxc
