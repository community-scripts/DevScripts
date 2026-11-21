#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Estcool9
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://github.com/morluto/rea

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

export DEBIAN_FRONTEND=noninteractive

msg_info "Installing REA analysis dependencies"
$STD apt install -y \
  binutils \
  binwalk \
  file \
  gdb \
  ltrace \
  procps \
  strace \
  tcpdump \
  tshark \
  unzip \
  7zip
msg_ok "Installed REA analysis dependencies"

NODE_VERSION="24" setup_nodejs
JAVA_VERSION="25" setup_java

fetch_and_deploy_gh_release "ghidra" "NationalSecurityAgency/ghidra" "prebuild" "latest" "/opt/ghidra" "ghidra_*_PUBLIC_*.zip"
GHIDRA_DIR="/opt/ghidra"
if [[ -z "$GHIDRA_DIR" || ! -x "$GHIDRA_DIR/support/analyzeHeadless" ]]; then
  msg_error "Ghidra headless installation was not found"
  exit 1
fi

JADX_VERSION="$(get_latest_github_release "1013503897/jadx-headless-mcp" false)"
JADX_TAG="${JADX_VERSION#v}"
JADX_BASE="https://github.com/1013503897/jadx-headless-mcp/releases/download/${JADX_VERSION}"
curl_with_retry "${JADX_BASE}/jadx-headless-mcp-${JADX_TAG}-all.jar" "/tmp/jadx-headless-mcp.jar"
curl_with_retry "${JADX_BASE}/jadx-headless-mcp.sha256" "/tmp/jadx-headless-mcp.sha256"
install -d -m 0755 /opt
install -m 0644 /tmp/jadx-headless-mcp.jar "/opt/jadx-headless-mcp-${JADX_TAG}-all.jar"
(cd /opt && sha256sum -c /tmp/jadx-headless-mcp.sha256)
msg_ok "Installed and verified JADX MCP adapter"

$STD npm install --global --allow-scripts=frida rea-agents@latest
REA_BIN="$(command -v rea)"
REA_PACKAGE_DIR="$(npm root -g)/rea-agents"
if [[ -z "$REA_BIN" || ! -f "$REA_PACKAGE_DIR/package.json" ]]; then
  msg_error "REA npm package installation could not be verified"
  exit 1
fi
msg_ok "Installed REA"

getent group rea >/dev/null || groupadd --system rea
id rea >/dev/null 2>&1 || useradd --system --home-dir /var/lib/rea --shell /usr/sbin/nologin --create-home --gid rea rea
install -d -o rea -g rea -m 0750 /var/lib/rea/.agents/skills
install -d -o rea -g rea -m 0750 /data/samples /data/projects /data/extracted /data/reports /data/checkpoints
cp -a "$REA_PACKAGE_DIR/skills/reverse-engineer-anything" /var/lib/rea/.agents/skills/
chown -R rea:rea /var/lib/rea /data

JAVA_HOME="$(dirname "$(dirname "$(readlink -f "$(command -v javac)")")")"
MCP_ALLOWED_HOSTS="${LOCAL_IP},127.0.0.1,localhost,rea-mcp"

cat <<REA_UNIT_EOF >/etc/systemd/system/rea-mcp.service
[Unit]
Description=REA Reverse Engineering MCP
Documentation=https://github.com/morluto/rea
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=rea
Group=rea
WorkingDirectory=/data
Environment=HOME=/var/lib/rea
Environment=PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
Environment=JAVA_HOME=$JAVA_HOME
Environment=GHIDRA_INSTALL_DIR=$GHIDRA_DIR
Environment=REA_ANALYSIS_PROVIDER=ghidra
Environment=REA_JADX_MCP_JAR=/opt/jadx-headless-mcp-${JADX_TAG}-all.jar
Environment=REA_GHIDRA_CHECKPOINT_DIR=/data/checkpoints
Environment=MCP_ALLOWED_HOSTS=$MCP_ALLOWED_HOSTS
ExecStart=$REA_BIN mcp --http --host 0.0.0.0 --allowed-hosts \${MCP_ALLOWED_HOSTS} --port 8765
Restart=on-failure
RestartSec=5
UMask=0077
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=full
ProtectHome=true
ProtectKernelTunables=true
ProtectControlGroups=true
LockPersonality=true
RestrictSUIDSGID=true
RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6
ReadWritePaths=/data /var/lib/rea /tmp

[Install]
WantedBy=multi-user.target
REA_UNIT_EOF

systemctl enable -q --now rea-mcp.service
if ! systemctl is-active --quiet rea-mcp.service; then
  msg_error "REA MCP service failed to start; inspect systemctl status rea-mcp"
  exit 1
fi
msg_ok "Created REA MCP service"

msg_info "Checking REA analysis providers"
runuser -u rea -- env HOME=/var/lib/rea JAVA_HOME="$JAVA_HOME" GHIDRA_INSTALL_DIR="$GHIDRA_DIR" REA_ANALYSIS_PROVIDER=ghidra REA_JADX_MCP_JAR="/opt/jadx-headless-mcp-${JADX_TAG}-all.jar" REA_GHIDRA_CHECKPOINT_DIR=/data/checkpoints "$REA_BIN" doctor --provider ghidra --json | jq -e '.healthy == true' >/dev/null
runuser -u rea -- env HOME=/var/lib/rea JAVA_HOME="$JAVA_HOME" GHIDRA_INSTALL_DIR="$GHIDRA_DIR" REA_ANALYSIS_PROVIDER=ghidra REA_JADX_MCP_JAR="/opt/jadx-headless-mcp-${JADX_TAG}-all.jar" REA_GHIDRA_CHECKPOINT_DIR=/data/checkpoints "$REA_BIN" doctor --provider jadx --json | jq -e '.healthy == true' >/dev/null
msg_ok "Ghidra and JADX providers are healthy"

motd_ssh
customize
cleanup_lxc
