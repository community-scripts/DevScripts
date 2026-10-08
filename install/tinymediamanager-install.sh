#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Borja Garduño (Borja-Garduno)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://www.tinymediamanager.org/

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt install -y \
  xvfb \
  x11vnc \
  novnc \
  websockify \
  openbox \
  x11-xserver-utils \
  x11-utils \
  libxrender1 \
  libxtst6 \
  libxi6 \
  libmediainfo0v5 \
  fonts-dejavu-core \
  xz-utils
msg_ok "Installed Dependencies"

ASSET_PATH=$(curl -fsSL https://release.tinymediamanager.org/ |
  grep -oE 'v5/dist/tinyMediaManager-[0-9.]+-linux-amd64\.tar\.xz' |
  head -1)
if [[ -z "${ASSET_PATH}" ]]; then
  msg_error "Could not resolve the official Linux amd64 download URL."
  exit 1
fi
ASSET_URL="https://release.tinymediamanager.org/${ASSET_PATH}"
VERSION=$(basename "${ASSET_PATH}" | grep -oE '[0-9]+(\.[0-9]+)+')

fetch_and_deploy_from_url "${ASSET_URL}" /opt/tinymediamanager
if [[ ! -f /opt/tinymediamanager/tinyMediaManager ]]; then
  msg_error "tinyMediaManager binary not found after deploy."
  exit 1
fi
chmod +x /opt/tinymediamanager/tinyMediaManager

msg_info "Configuring tinyMediaManager"
mkdir -p /opt/tinymediamanager_data
cat <<EOF >/opt/tinymediamanager/launcher-extra.yml
javaHome: ""
jvmOpts:
  - "-Dtmm.contentfolder=/opt/tinymediamanager_data"
  - "-Dtmm.noupdate=true"
  - "-Dtmm.legacy.filechooser=true"
env:
  - "_JAVA_AWT_WM_NONREPARENTING=1"
EOF
echo "${VERSION}" >~/.tinymediamanager
if ! mountpoint -q /media/movies; then
  mkdir -p /media/movies
fi
if ! mountpoint -q /media/tvshows; then
  mkdir -p /media/tvshows
fi
msg_ok "Configured tinyMediaManager"

msg_info "Configuring Openbox"
mkdir -p /root/.config/openbox
cat <<'EOF' >/root/.config/openbox/rc.xml
<?xml version="1.0" encoding="UTF-8"?>
<openbox_config xmlns="http://openbox.org/3.4/rc">
  <applications>
    <application class="*">
      <maximized>true</maximized>
    </application>
  </applications>
</openbox_config>
EOF
msg_ok "Configured Openbox"

msg_info "Creating Services"
cat <<EOF >/etc/systemd/system/xvfb.service
[Unit]
Description=Virtual Framebuffer X Server
After=network.target

[Service]
Type=simple
ExecStartPre=/bin/sh -c 'rm -f /tmp/.X1-lock'
ExecStart=/usr/bin/Xvfb :1 -screen 0 1920x1080x24
ExecStartPost=/bin/sh -c 'sleep 1 && DISPLAY=:1 /usr/bin/xset s off && DISPLAY=:1 /usr/bin/xset s noblank && DISPLAY=:1 /usr/bin/xset -dpms'
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

cat <<EOF >/etc/systemd/system/openbox.service
[Unit]
Description=Openbox Window Manager
After=xvfb.service
Requires=xvfb.service

[Service]
Type=simple
Environment=DISPLAY=:1
ExecStart=/usr/bin/openbox
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

cat <<EOF >/etc/systemd/system/tinymediamanager.service
[Unit]
Description=tinyMediaManager
After=openbox.service
Requires=openbox.service

[Service]
Type=simple
User=root
Environment=DISPLAY=:1
WorkingDirectory=/opt/tinymediamanager
ExecStartPre=/bin/sleep 2
ExecStart=/opt/tinymediamanager/tinyMediaManager
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

cat <<EOF >/etc/systemd/system/x11vnc.service
[Unit]
Description=x11vnc Server
After=tinymediamanager.service
Requires=xvfb.service

[Service]
Type=simple
ExecStart=/usr/bin/x11vnc -display :1 -forever -shared -rfbport 5900 -nopw -noipv6 -xkb -noxdamage -nowf -nowcr -wait 50 -defer 50
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

cat <<EOF >/etc/systemd/system/novnc.service
[Unit]
Description=noVNC WebSocket Proxy
After=x11vnc.service
Requires=x11vnc.service

[Service]
Type=simple
ExecStart=/usr/bin/websockify --web=/usr/share/novnc 6080 localhost:5900
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl enable -q --now xvfb
sleep 2
systemctl enable -q --now openbox
sleep 1
systemctl enable -q --now tinymediamanager
sleep 3
systemctl enable -q --now x11vnc
sleep 1
systemctl enable -q --now novnc
msg_ok "Created Services"

motd_ssh
customize
cleanup_lxc
