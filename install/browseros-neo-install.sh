#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: masterde
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://github.com/browseros-ai/BrowserOS

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

# libasound2t64 goes first: the .deb's unversioned "Depends: libasound2" can
# otherwise resolve to an OSS shim, and BrowserOS Neo then fails to start.
msg_info "Installing Dependencies"
$STD apt install -y libasound2t64
$STD apt install -y \
  tigervnc-standalone-server \
  tigervnc-tools \
  openbox \
  novnc \
  websockify \
  supervisor \
  nginx \
  openssl \
  fonts-liberation \
  fonts-noto-core \
  fonts-noto-color-emoji
msg_ok "Installed Dependencies"
systemctl disable -q --now supervisor

fetch_and_deploy_gh_release "browseros-neo" "browseros-ai/BrowserOS" "binary" "latest" "" "" "browserclaw/v"

msg_info "Configuring BrowserOS Neo"
mkdir -p /opt/browseros-neo_data/{profile,browserclaw,downloads} /etc/browseros-neo /var/log/browseros-neo /root/.config/gtk-3.0
ln -sfn /opt/browseros-neo_data/downloads /root/Downloads
VIEWER_PASS=$(random_password)
MCP_TOKEN=$(openssl rand -hex 32)
cat <<EOF >/opt/browseros-neo_data/.env
VIEWER_USER=neo
VIEWER_PASSWORD=${VIEWER_PASS}
MCP_TOKEN=${MCP_TOKEN}
EOF
chmod 600 /opt/browseros-neo_data/.env

# Openbox only keeps BrowserOS Neo maximized and re-fits it when noVNC resizes the
# screen; there is no desktop or taskbar, so the minimize button is hidden too.
cat <<'EOF' >/etc/browseros-neo/openbox-rc.xml
<?xml version="1.0" encoding="UTF-8"?>
<openbox_config xmlns="http://openbox.org/3.4/rc">
  <focus>
    <focusNew>yes</focusNew>
    <followMouse>no</followMouse>
  </focus>
  <placement>
    <policy>Smart</policy>
    <center>yes</center>
  </placement>
  <desktops>
    <number>1</number>
  </desktops>
  <keyboard/>
  <applications>
    <application type="normal">
      <decor>no</decor>
      <maximized>yes</maximized>
    </application>
  </applications>
</openbox_config>
EOF
cat <<'EOF' >/root/.config/gtk-3.0/settings.ini
[Settings]
gtk-decoration-layout=:maximize,close
EOF
# --no-sandbox is required to run Chromium as root; drop its warning bar for that flag.
mkdir -p /etc/chromium/policies/managed
cat <<'EOF' >/etc/chromium/policies/managed/browseros-neo.json
{"CommandLineFlagSecurityWarningsEnabled": false}
EOF
msg_ok "Configured BrowserOS Neo"

msg_info "Configuring Nginx"
cat <<EOF >/etc/nginx/browseros-neo.htpasswd
neo:$(openssl passwd -apr1 "${VIEWER_PASS}")
EOF
chown root:www-data /etc/nginx/browseros-neo.htpasswd
chmod 640 /etc/nginx/browseros-neo.htpasswd
# Port 9010 rewrites Host to loopback: BrowserOS Neo's MCP server only accepts
# Host: localhost/127.0.0.1 (DNS-rebinding guard) and has no setting to widen it.
cat <<EOF >/etc/nginx/sites-available/browseros-neo
map \$http_upgrade \$connection_upgrade {
    default upgrade;
    ''      close;
}

server {
    listen 6080;
    auth_basic "BrowserOS Neo";
    auth_basic_user_file /etc/nginx/browseros-neo.htpasswd;

    location = / {
        return 302 /vnc.html?autoconnect=1&resize=remote&reconnect=1&reconnect_delay=1000;
    }

    location / {
        proxy_pass http://127.0.0.1:6081;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \$connection_upgrade;
        proxy_read_timeout 1d;
    }
}

server {
    listen 9010;

    location / {
        if (\$http_authorization != "Bearer ${MCP_TOKEN}") {
            return 401;
        }
        proxy_pass http://127.0.0.1:19010;
        proxy_http_version 1.1;
        proxy_set_header Host 127.0.0.1:19010;
        proxy_set_header Origin "";
        proxy_set_header Connection "";
        proxy_buffering off;
        proxy_cache off;
        proxy_read_timeout 1d;
    }
}
EOF
nginx_enable_site "browseros-neo"
msg_ok "Configured Nginx"

msg_info "Creating Service"
cat <<'EOF' >/etc/browseros-neo/supervisord.conf
[supervisord]
nodaemon=true
user=root
logfile=/var/log/browseros-neo/supervisord.log
pidfile=/run/browseros-neo/supervisord.pid

[unix_http_server]
file=/run/browseros-neo/supervisor.sock
chmod=0700

[supervisorctl]
serverurl=unix:///run/browseros-neo/supervisor.sock

[rpcinterface:supervisor]
supervisor.rpcinterface_factory=supervisor.rpcinterface:make_main_rpcinterface

[program:xvnc]
command=/usr/bin/Xvnc :1 -geometry 1600x1000 -depth 24 -SecurityTypes None -localhost -rfbport 5900 -AlwaysShared -nolisten tcp
priority=100
autorestart=true
stdout_logfile=/var/log/browseros-neo/xvnc.log
redirect_stderr=true

[program:openbox]
environment=DISPLAY=":1",HOME="/root"
command=/usr/bin/openbox --config-file /etc/browseros-neo/openbox-rc.xml
priority=200
autorestart=true
stdout_logfile=/var/log/browseros-neo/openbox.log
redirect_stderr=true

[program:vncconfig]
environment=DISPLAY=":1"
command=/usr/bin/vncconfig -nowin
priority=200
autorestart=true
stdout_logfile=/var/log/browseros-neo/vncconfig.log
redirect_stderr=true

[program:websockify]
command=/usr/bin/websockify --web /usr/share/novnc 127.0.0.1:6081 127.0.0.1:5900
priority=200
autorestart=true
stdout_logfile=/var/log/browseros-neo/websockify.log
redirect_stderr=true

[program:browseros-neo]
environment=DISPLAY=":1",HOME="/root",LANG="C.UTF-8",XDG_RUNTIME_DIR="/run/browseros-neo",BROWSERCLAW_DIR="/opt/browseros-neo_data/browserclaw",BROWSERCLAW_MODE="hosted"
command=/usr/bin/browserclaw --no-sandbox --user-data-dir=/opt/browseros-neo_data/profile --no-first-run --no-default-browser-check --password-store=basic --browseros-proxy-port=19010 --browseros-cdp-port=9110 --browseros-server-port=9210 --hide-crash-restore-bubble --start-maximized
priority=300
autorestart=true
startsecs=5
stopwaitsecs=20
stdout_logfile=/var/log/browseros-neo/browseros-neo.log
redirect_stderr=true
EOF
# The profile lock outlives an unclean stop; nothing else uses this profile.
cat <<'EOF' >/etc/systemd/system/browseros-neo.service
[Unit]
Description=BrowserOS Neo
After=network.target

[Service]
Type=simple
RuntimeDirectory=browseros-neo
RuntimeDirectoryMode=0700
ExecStartPre=/bin/rm -f /opt/browseros-neo_data/profile/SingletonLock /opt/browseros-neo_data/profile/SingletonSocket /opt/browseros-neo_data/profile/SingletonCookie
ExecStart=/usr/bin/supervisord -c /etc/browseros-neo/supervisord.conf -n
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now browseros-neo
msg_ok "Created Service"

msg_info "Waiting for BrowserOS Neo"
for _ in $(seq 1 120); do
  curl -fsS http://127.0.0.1:19010/system/ready >/dev/null 2>&1 && break
  sleep 1
done
curl -fsS -X PUT http://127.0.0.1:19010/api/v1/settings/agent \
  -H 'Content-Type: application/json' -d '{"humanHelpEnabled":false}' >/dev/null
msg_ok "BrowserOS Neo is ready"

motd_ssh
customize
cleanup_lxc
