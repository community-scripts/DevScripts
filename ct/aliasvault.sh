#!/usr/bin/env bash
_CS_DEFAULT_URL="https://raw.githubusercontent.com/community-scripts/DevScripts/main"
_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../core}/core/build.func"
source "$_cs_boot" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/build.func")
# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ) | Co-Author: Jan Wiebe Klijnsma (jwklijnsma)
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://aliasvault.net

APP="AliasVault"
var_tags="${var_tags:-security;passwords;privacy}"
var_cpu="${var_cpu:-4}"
var_ram="${var_ram:-6144}"
var_disk="${var_disk:-24}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-no}" # wasm-pack prebuild and the Microsoft .NET apt repo are pinned to amd64
var_unprivileged="${var_unprivileged:-1}"
var_testurl="${var_testurl:-https://github.com/community-scripts/DevScripts/issues/1827}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -f /opt/aliasvault/.env ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  if [[ ! -x /usr/local/bin/aliasvault-configure ]]; then
    msg_error "This container was created by the pre-0.31 AliasVault script (Blazor client). Export your vaults and recreate the container."
    exit
  fi

  if check_for_gh_release "aliasvault" "aliasvault/aliasvault"; then
    msg_info "Stopping AliasVault"
    systemctl stop aliasvault-api aliasvault-admin aliasvault-smtp aliasvault-taskrunner
    msg_ok "Stopped AliasVault"

    create_backup /opt/aliasvault/.env

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "aliasvault" "aliasvault/aliasvault" "tarball"

    restore_backup

    msg_info "Building AliasVault Core Libraries"
    source "$HOME/.cargo/env"
    $STD rustup target add wasm32-unknown-unknown
    cd /opt/aliasvault/core
    $STD bash build-and-distribute.sh --web
    msg_ok "Built AliasVault Core Libraries"

    msg_info "Building AliasVault Web Client"
    cd /opt/aliasvault/apps/web
    $STD npm ci --no-audit --no-fund
    $STD npm run build
    cp -r /opt/aliasvault/apps/web/dist /opt/aliasvault/www
    msg_ok "Built AliasVault Web Client"

    msg_info "Building AliasVault Server"
    cd /opt/aliasvault/apps/server
    $STD dotnet restore aliasvault.sln
    $STD dotnet publish AliasVault.Api/AliasVault.Api.csproj -c Release -o /opt/aliasvault/api --no-restore /p:UseAppHost=false
    $STD dotnet publish AliasVault.Admin/AliasVault.Admin.csproj -c Release -o /opt/aliasvault/admin --no-restore /p:UseAppHost=false
    $STD dotnet publish AliasVault.SmtpService/AliasVault.SmtpService.csproj -c Release -o /opt/aliasvault/smtp --no-restore /p:UseAppHost=false
    $STD dotnet publish AliasVault.TaskRunner/AliasVault.TaskRunner.csproj -c Release -o /opt/aliasvault/taskrunner --no-restore /p:UseAppHost=false
    $STD dotnet publish Utilities/AliasVault.InstallCli/AliasVault.InstallCli.csproj -c Release -o /opt/aliasvault/installcli --no-restore /p:UseAppHost=false
    msg_ok "Built AliasVault Server"

    msg_info "Starting AliasVault"
    systemctl restart nginx
    systemctl start aliasvault.target
    msg_ok "Started AliasVault"
    msg_ok "Updated successfully!"
  fi
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW}Access it using the following URL:${CL}"
echo -e "${GATEWAY}${BGN}https://${IP}${CL}"
echo -e "${INFO}${YW} Admin Panel:${CL} ${GATEWAY}${BGN}https://${IP}/admin${CL}"
echo -e "${INFO}${YW} Admin credentials:${CL} ${BGN}cat ~/aliasvault.creds${CL}"
