# 🤖 AI Working Instructions for DevScripts

> **For every AI assistant (GitHub Copilot, Claude, ChatGPT, Codex, …) producing scripts for this project.**

This is a **work instruction, not a style guide**. Every rule below is mandatory.
A pull request that breaks any of them is rejected without review — reviewer time
is the scarce resource here, not generation time.

Two rules override everything else:

1. **Do not invent.** If a helper exists, call it. If you are unsure whether one
   exists, search `tools.func` before writing a single line of your own.
2. **Do not guess the application.** Read its upstream repository first
   (see "Research the upstream project"). A script written from assumptions about
   how an app installs is worthless, however clean the bash looks.

If a rule genuinely cannot be followed for a specific application, **stop and say so
in the PR description**. Do not work around it silently.

## 🎯 Core Principles

### 1. **Maximum Use of `tools.func` Functions**

We have an extensive library of helper functions. **NEVER** implement your own solutions when a function already exists!

### 2. **No Pointless Variables**

Only create variables when they:

- Are used multiple times
- Improve readability
- Are intended for configuration

### 3. **Consistent Script Structure**

All scripts follow an identical structure. Deviations are not acceptable.

### 4. **Bare-Metal Installation**

We do **NOT use Docker** for our installation scripts. All applications are installed directly on the system.

**Scoped exception:** `ensure_docker` / `setup_docker` exist in `tools.func`, but only
for `tools/addon/*.sh` scripts that intentionally manage a Docker Compose stack (e.g.
`arcane.sh`, `mqttx.sh`) — never for `ct/`/`install/` app scripts, which stay bare-metal.

**If the application can only be installed via Docker, stop.** Do not wrap a container
runtime, do not translate a `Dockerfile` into `docker run`, do not submit the PR. Say in
the issue that the app is Docker-only and leave it. A Docker-based `ct/` script is
rejected on sight.

### 5. **No Functions of Your Own**

`ct/` and `install/` scripts define exactly one function: `update_script()` in the CT
script. Nothing else. No `run_app()`, no `install_deps()`, no wrappers around a helper.
Write the commands in order, top to bottom.

**One exception:** the per-OS functions the engine dispatches to
(`setup_alpine`, `update_deb_based`, …). Those are a contract, not helpers of your
own — see "Alpine and Multi-OS Scripts".

### 6. **Python Goes Through `uv`, Always**

No `python3 -m venv`, no `pip install`, no `virtualenv`, no `python3-pip` in the
dependency list. Use `setup_uv` and then `uv`. See "Python Applications".

### 7. **Write the Application's Name, Not a Placeholder**

Every string a user sees names the real tool: `msg_info "Stopping Nautobot"`, not
`msg_info "Stopping ${APPLICATION}"` or `"Stopping $APP"`. Placeholders belong in this
document, never in a script you submit.

---

## 🔬 Research the Upstream Project First

Before writing anything, open the application's repository and read it. The files
below tell you what the install actually needs. Guessing produces the scripts we
reject.

| File | Read it for |
| ---- | ----------- |
| `Dockerfile` | The real install sequence: build steps, runtime version, entrypoint, required system packages. This is the single most useful file — it is the upstream author's own install script. |
| `docker-compose.yml` | Extra services the app expects: PostgreSQL, MariaDB, Redis, Valkey, MongoDB, MeiliSearch. Each one maps to a `setup_*` helper. Also reveals volumes (→ what to back up) and ports. |
| `.env.example` / `.env.sample` | Every configuration key the app reads, and which ones are mandatory. Your `.env` must match these names exactly. |
| `package.json` | Node only: the `engines` field gives the required Node major for `NODE_VERSION`; `scripts.build` gives the build command; `packageManager` says npm vs pnpm vs yarn. |
| `pyproject.toml` / `uv.lock` / `requirements.txt` | Python only: the required Python version for `PYTHON_VERSION`, and whether `uv sync` (lockfile present) or `uv pip install -r requirements.txt` applies. |
| `go.mod`, `Cargo.toml`, `composer.json`, `*.csproj` | The language version to pass to the matching `setup_*`. |
| `README` / `docs/` install page | Migrations, first-run commands, admin bootstrap. |

Name the source in one line of the PR description, e.g. "Steps from the upstream
Dockerfile; Node 22, PostgreSQL 17."

**Two traps:**

- A `Dockerfile` that only copies a prebuilt artifact means the real build lives in
  CI. Look at `.github/workflows/` for the build, and prefer
  `fetch_and_deploy_gh_release` over rebuilding from source.
- A `docker-compose.yml` service you skip is a missing dependency at runtime, not a
  simplification. If the app needs Redis, call `setup_redis` — do not hope it is optional.

---

## 🧭 Deciding `var_arm64`

The template ships this line commented out:

```bash
#var_arm64="${var_arm64:-no}" # unset = ask the user; set yes/no only when verified
```

**Do not leave it commented and move on.** Decide, and give the reason in one line of the PR:

- `var_arm64="${var_arm64:-yes}"` — the project publishes `arm64`/`aarch64` release
  assets, or is pure Node/Python/PHP with no native prebuilt binaries.
- `var_arm64="${var_arm64:-no}"` — release assets are `amd64` only, or the install
  pulls an x86-only binary (many Go/Rust projects, anything with a bundled Chromium).
- Leave it commented **only** if you genuinely cannot tell from the release assets —
  and then say so.

Check by listing the release assets of the upstream repo, not by assuming.

---

## 🏔️ Alpine and Multi-OS Scripts

An application is offered on Alpine in one of two shapes. Pick one; do not invent a third.

### Shape A — Alpine only

The app has no Debian variant. One pair of files, prefixed:

- `ct/alpine-<app>.sh`, `install/alpine-<app>-install.sh`
- `APP="Alpine-<AppName>"`, `var_tags` contains `alpine`
- `var_os="${var_os:-alpine}"`, `var_version="${var_version:-3.24}"` (the Alpine release, not a Debian one)
- Smaller defaults are the point: typically `var_ram` 256–512, `var_disk` 1–3

### Shape B — Debian and Alpine in one script

The app runs on both. **One** `ct/<app>.sh` and **one** `install/<app>-install.sh`,
never a second copy. The CT script asks, then branches only the resource defaults:

```bash
APP="Adguard"
var_tags="${var_tags:-adblock}"
var_cpu="${var_cpu:-1}"
var_unprivileged="${var_unprivileged:-1}"
if [[ -z "${var_os:-}" ]] && command -v pveversion >/dev/null 2>&1; then
  var_os=$(msg_menu "Choose the container OS"     "debian" "Debian 13"     "alpine" "Alpine (smaller footprint)")
fi

if [[ "${var_os:-}" == "alpine" ]]; then
  var_ram="${var_ram:-256}"
  var_disk="${var_disk:-1}"
  var_version="${var_version:-3.24}"
else
  var_ram="${var_ram:-512}"
  var_disk="${var_disk:-2}"
  var_version="${var_version:-13}"
fi
```

The `-z "${var_os:-}"` guard matters: it lets `var_os=alpine bash -c ...` skip the menu.

### The dispatch contract

The engine calls one function per OS family. **Defining the function is how your script
declares support for that family** — if it is missing, the engine aborts with a clear
error instead of silently doing nothing.

| You call | Engine runs | Define in |
| -------- | ----------- | --------- |
| `run_os_setup` | `setup_deb_based` / `setup_alpine` / `setup_rhel_based` / `setup_suse_based` / `setup_arch_based` / `setup_gentoo_based` | install script |
| `run_os_update` | `update_deb_based` / `update_alpine` / … | CT script, inside `update_script()` |

Install script: define the families you support, then call `run_os_setup` once, before
the footer.

```bash
setup_deb_based() {
  msg_info "Installing AdGuard Home"
  $STD apt install -y adguardhome
  msg_ok "Installed AdGuard Home"
}

setup_alpine() {
  msg_info "Installing AdGuard Home"
  $STD apk add --no-cache adguardhome
  msg_ok "Installed AdGuard Home"
}

run_os_setup

motd_ssh
customize
cleanup_lxc
```

CT script: same idea, dispatched from `update_script()`.

```bash
update_deb_based() {
  msg_error "Adguard Home can only be updated via the user interface."
}

update_alpine() {
  msg_info "Updating AdGuard Home"
  $STD /opt/AdGuardHome/AdGuardHome --update
  msg_ok "Updated AdGuard Home"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  run_os_update
}
```

### What differs on Alpine

| | Debian | Alpine |
| --- | ------ | ------ |
| Packages | `$STD apt install -y ...` | `$STD apk add --no-cache ...` |
| Service unit | `/etc/systemd/system/<name>.service` | `/etc/init.d/<name>` (`#!/sbin/openrc-run`) |
| Enable + start | `systemctl enable -q --now <name>` | `rc-update add <name> default` + `rc-service <name> start` |
| Restart | `systemctl restart <name>` | `rc-service <name> restart` |
| OS upgrade | handled by `update_os` | `$STD apk -U upgrade` |

OpenRC service file:

```bash
cat <<EOF >/etc/init.d/adguardhome
#!/sbin/openrc-run
name="AdGuardHome"
description="AdGuard Home Service"
command="/opt/AdGuardHome/AdGuardHome"
command_background="yes"
pidfile="/run/adguardhome.pid"
EOF
chmod +x /etc/init.d/adguardhome
```

There is no systemd on Alpine: `systemctl`, `daemon-reload` and `.service` files in an
`setup_alpine` block are a guaranteed failure. Many `setup_*` helpers are Debian-only —
check before calling one from an Alpine branch.

---

## 📁 Script Types and Their Structure

### CT Script (`ct/AppName.sh`)

```bash
#!/usr/bin/env bash
_CS_DEFAULT_URL="https://raw.githubusercontent.com/community-scripts/DevScripts/main"
_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../core}/core/build.func"
source "$_cs_boot" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/build.func")

# Copyright (c) 2021-2026 community-scripts ORG
# Author: AuthorName (GitHubUsername)
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://application-url.com

APP="AppName"
var_tags="${var_tags:-tag1;tag2;tag3}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-8}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/appname ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "appname" "owner/repo"; then
    msg_info "Stopping Service"
    systemctl stop appname
    msg_ok "Stopped Service"

    create_backup /opt/appname/.env

    CLEAN_INSTALL=1 CLEAN_INSTALL_KEEP="data" fetch_and_deploy_gh_release "appname" "owner/repo" "tarball"

    restore_backup

    msg_info "Starting Service"
    systemctl start appname
    msg_ok "Started Service"
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
echo -e "${GATEWAY}${BGN}http://${IP}:PORT${CL}"
```

### Install Script (`install/AppName-install.sh`)

```bash
#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: AuthorName (GitHubUsername)
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://application-url.com

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt install -y \
  dependency1 \
  dependency2
msg_ok "Installed Dependencies"

NODE_VERSION="22" setup_nodejs

fetch_and_deploy_gh_release "appname" "owner/repo" "tarball"

msg_info "Setting up Application"
cd /opt/appname
$STD npm ci
$STD npm run build
msg_ok "Set up Application"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/appname.service
[Unit]
Description=AppName Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/appname
ExecStart=/path/to/executable
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now appname
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc
```

---

## 🔧 Available Helper Functions

### Release Management

| Function                      | Description                           | Example                                                    |
| ----------------------------- | ------------------------------------- | ---------------------------------------------------------- |
| `fetch_and_deploy_gh_release` | Fetches and installs GitHub Release   | `fetch_and_deploy_gh_release "app" "owner/repo" "tarball"` |
| `check_for_gh_release`        | Checks for new version                | `if check_for_gh_release "app" "owner/repo"; then`         |
| `get_latest_github_release`   | Returns latest release version string | `VERSION=$(get_latest_github_release "owner/repo")`        |
| `fetch_and_deploy_gl_release` / `fetch_and_deploy_gl_tag` | GitLab equivalents (self-hosted or gitlab.com) | `GITLAB_URL="https://gitlab.example.org" fetch_and_deploy_gl_release "app" "owner/repo" "tarball"` |
| `fetch_and_deploy_codeberg_release` / `check_for_codeberg_release` | Codeberg equivalents | `fetch_and_deploy_codeberg_release "app" "owner/repo" "tarball"` |
| `fetch_and_deploy_from_url`   | Last resort for a fixed URL when no release API fits | still avoids hand-rolled curl/tar |
| `get_latest_gitlab_release "owner/repo" [strip_v]` / `get_latest_codeberg_release "owner/repo"` | Version string only, GitLab/Codeberg equivalents of `get_latest_github_release` | `VERSION=$(get_latest_gitlab_release "owner/repo")` |

**Repos that only publish tags, not Releases:**

| Function                      | Description                                                               | Example                                              |
| ------------------------------ | ---------------------------------------------------------------------------| ------------------------------------------------------ |
| `fetch_and_deploy_gh_tag`     | Deploys from a tag instead of a GitHub Release                            | `fetch_and_deploy_gh_tag "guacd" "apache/guacamole-server"` |
| `check_for_gh_tag`            | Update check for tag-only repos, same interface as `check_for_gh_release` | `if check_for_gh_tag "guacd" "apache/guacamole-server"; then` |
| `get_latest_gh_tag "owner/repo" [prefix]` | Latest tag name, sorted with `sort -V`                         | `TAG=$(get_latest_gh_tag "owner/repo")`              |
| `get_latest_gl_tag "owner/repo" ["glob"]` | Latest GitLab tag, optionally filtered by glob                 | `get_latest_gl_tag "owner/repo" "web-v*"`            |

**Repos with no releases or tags at all — deployed straight from a branch (e.g. RSSHub):**

| Function                      | Description                                                                                     | Example                                              |
| ------------------------------ | --------------------------------------------------------------------------------------------------| ------------------------------------------------------ |
| `fetch_and_deploy_gh_branch`  | Shallow-clones on first run, fast-forwards on later runs; records the short SHA in `~/.<app>`     | `fetch_and_deploy_gh_branch "app" "owner/repo" "main"` |
| `check_for_gh_branch`         | Compares the recorded SHA against the branch tip                                                  | `if check_for_gh_branch "app" "owner/repo"; then`    |

Never hand-roll `git clone`/`git pull` for a tag-only or rolling-release app — these two
pairs exist specifically to avoid that (see Anti-Pattern 27).

**Modes for `fetch_and_deploy_gh_release`:**

```bash
# Tarball/Source (Standard) - always specify "tarball" explicitly
fetch_and_deploy_gh_release "appname" "owner/repo" "tarball"

# Binary (.deb)
fetch_and_deploy_gh_release "appname" "owner/repo" "binary"

# Prebuilt Archive
fetch_and_deploy_gh_release "appname" "owner/repo" "prebuild" "latest" "/opt/appname" "filename.tar.gz"

# Single Binary
fetch_and_deploy_gh_release "appname" "owner/repo" "singlefile" "latest" "/opt/appname" "binary-linux-amd64"
```

**Clean Install Flag:**

```bash
CLEAN_INSTALL=1 fetch_and_deploy_gh_release "appname" "owner/repo" "tarball"
```

**Pre-release projects:** `/releases/latest` on GitHub hides pre-releases. For projects
that only ship betas (e.g. RustFS), set `GH_INCLUDE_PRERELEASE=1` — it applies to both
`fetch_and_deploy_gh_release` and `check_for_gh_release`:

```bash
GH_INCLUDE_PRERELEASE=1 fetch_and_deploy_gh_release "app" "owner/repo" "prebuild" "latest" "/opt/app" "app-linux-amd64.zip"
if GH_INCLUDE_PRERELEASE=1 check_for_gh_release "app" "owner/repo"; then
```

**Version file:** After `fetch_and_deploy_gh_release`, the deployed version is stored in `~/.appname`. You can read it with `cat ~/.appname` — useful when you need the version later (e.g. for build-time environment variables).

### Runtime/Language Setup

| Function       | Variable(s)                   | Example                                              |
| -------------- | ----------------------------- | ---------------------------------------------------- |
| `setup_nodejs` | `NODE_VERSION`, `NODE_MODULE` | `NODE_VERSION="22" setup_nodejs`                     |
| `setup_uv`     | `PYTHON_VERSION`              | `PYTHON_VERSION="3.12" setup_uv`                     |
| `setup_go`     | `GO_VERSION`                  | `GO_VERSION="1.22" setup_go`                         |
| `setup_rust`   | `RUST_TOOLCHAIN`, `RUST_CRATES` | `RUST_CRATES="monolith" setup_rust`                |
| `setup_ruby`   | `RUBY_VERSION`                | `RUBY_VERSION="3.3" setup_ruby`                      |
| `setup_java`   | `JAVA_VERSION`                | `JAVA_VERSION="21" setup_java`                       |
| `setup_php`    | `PHP_VERSION`, `PHP_MODULE`   | `PHP_VERSION="8.3" PHP_MODULE="redis,gd" setup_php`  |

### Database Setup

| Function              | Variable(s)                          | Example                                                     |
| --------------------- | ------------------------------------ | ----------------------------------------------------------- |
| `setup_postgresql`    | `PG_VERSION`, `PG_MODULES`           | `PG_VERSION="16" setup_postgresql`                          |
| `setup_postgresql_db` | `PG_DB_NAME`, `PG_DB_USER`           | `PG_DB_NAME="mydb" PG_DB_USER="myuser" setup_postgresql_db` |
| `setup_mariadb`       | -                                     | `setup_mariadb`                                              |
| `setup_mariadb_db`    | `MARIADB_DB_NAME`, `MARIADB_DB_USER` | `MARIADB_DB_NAME="mydb" setup_mariadb_db`                   |
| `setup_mysql`         | `MYSQL_VERSION`                      | `setup_mysql`                                               |
| `setup_mysql_db`      | `MYSQL_DB_NAME`, `MYSQL_DB_USER`     | `MYSQL_DB_NAME="mydb" setup_mysql_db`                       |
| `setup_mongodb`       | `MONGO_VERSION`                      | `setup_mongodb`                                             |
| `setup_clickhouse`    | -                                    | `setup_clickhouse`                                          |
| `setup_meilisearch`   | -                                    | `setup_meilisearch`                                          |

### Tools & Utilities

| Function            | Description                        |
| ------------------- | ---------------------------------- |
| `setup_adminer`     | Installs Adminer for DB management |
| `setup_composer`    | Install PHP Composer               |
| `setup_ffmpeg`      | Install FFmpeg (see below)         |
| `setup_imagemagick` | Install ImageMagick                |
| `setup_gs`          | Install Ghostscript                |
| `setup_hwaccel`     | Configure hardware acceleration    |
| `setup_yq`          | Install `yq` (YAML processor)      |
| `setup_nltk`        | Install Python NLTK + data corpora |

### Repos, Services, TLS & Downloads

| Function                                                        | Description                                                                                  | Example |
| ------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------ | --------- |
| `setup_deb822_repo "name" "<gpg_url>" "<repo_url>" "<suite>" ["component"] ["archs"]` | Adds a 3rd-party APT repo the deb822 way — never hand-roll GPG keys + sources.list | `setup_deb822_repo "grafana" "https://apt.grafana.com/gpg.key" "https://apt.grafana.com" "stable" "main"` |
| `download_gpg_key "<url>" "<output_path>" ["dearmor"]`          | Fallback when a repo isn't deb822-shaped — retries, validates, mirrors, and auto-detects binary vs. ASCII-armored keys | `download_gpg_key "https://example.com/key.asc" "/etc/apt/keyrings/example.gpg" "dearmor"` |
| `verify_gpg_fingerprint "<key_file>" "<expected_fingerprint>"`  | Confirms a downloaded key matches the expected fingerprint before trusting it                | pair with `download_gpg_key` for repos you don't control |
| `prepare_repository_setup "<pkg>..."`                           | Cleans stale repos/keyrings for the named packages and validates APT before adding a new source | `prepare_repository_setup "mariadb" "mysql"` |
| `curl_with_retry "<url>" "<outfile>" [opts]`                    | Retrying curl (honors `CURL_RETRIES`/`CURL_TIMEOUT`) — use for any download not covered by `fetch_and_deploy_*` | never hand-roll a bare `curl`/`wget` loop |
| `install_packages_with_retry <pkg...>`                          | APT install with retry                                                                        | `install_packages_with_retry nginx redis` |
| `upgrade_packages_with_retry <pkg...>`                          | APT upgrade with retry, for specific packages                                                | `upgrade_packages_with_retry "mariadb-server" "mariadb-client"` |
| `safe_service_restart <svc>`                                    | Restarts a systemd service, tolerant of a unit that isn't running yet                        | `safe_service_restart nginx` |
| `create_self_signed_cert "<app>"`                               | Writes `/etc/ssl/<app>/<app>.{crt,key}` — SAN covers hostname + container IP + localhost; never hand-roll `openssl` | see [Secure-Context Web Apps](#secure-context-web-apps-https) below |
| `arch_resolve "x86_64" "arm64"`                                 | Returns the arch-correct token for a multi-arch release asset pattern instead of hardcoding it | `fetch_and_deploy_gh_release "pdfcpu" "pdfcpu/pdfcpu" "prebuild" "latest" "/opt/pdfcpu" "pdfcpu_*_Linux_$(arch_resolve "x86_64" "arm64").tar.xz"` |

Call it inline inside the asset-pattern string, as above. Don't pre-assign the result to
a variable unless that value is genuinely read more than once:

```bash
# ❌ WRONG - ARCH is only ever read once; the variable adds nothing
ARCH=$(arch_resolve)
fetch_and_deploy_gh_release "safebucket" "safebucket/safebucket" "singlefile" "latest" "/opt/safebucket" "safebucket-linux-${ARCH}"

# ✅ CORRECT - call it inline
fetch_and_deploy_gh_release "safebucket" "safebucket/safebucket" "singlefile" "latest" "/opt/safebucket" "safebucket-linux-$(arch_resolve)"
```

This is the same "No Pointless Variables" principle from the top of this document — it
just comes up often enough with `arch_resolve` specifically to call out here.

### Secure-Context Web Apps (HTTPS)

Browser APIs like `crypto.subtle` (Web Crypto / PKCE), `navigator.storage.getDirectory`
(OPFS), service workers, and `SharedArrayBuffer` are only available in a **secure
context** (HTTPS or `localhost`). An app that uses any of them breaks over plain
`http://<IP>` with errors such as `crypto.subtle is unavailable in insecure contexts` or
`Cannot read properties of undefined (reading 'getDirectory')`. When the app (SPA or
backend console) relies on these:

- Terminate TLS with `create_self_signed_cert "<app>"` (its SAN already covers the
  container IP) behind an nginx `listen 443 ssl` server, redirect `:80 → :443`, and
  proxy to the app on an internal port (or serve the static root directly). Enable the
  vhost with `nginx_enable_site "<app>"`, same as any other site.
- If the source uses `SharedArrayBuffer` (grep for it), also set cross-origin isolation
  on the HTTPS server: `add_header Cross-Origin-Opener-Policy same-origin always;` and
  `add_header Cross-Origin-Embedder-Policy require-corp always;`.
- In `notes`, tell users to accept the self-signed certificate (on every port the login
  flow touches) and point them at the `https://` URL.

**FFmpeg acquisition (`FFMPEG_TYPE`):**

| Value                        | Source                                    | When to use                                        |
| ---------------------------- | ----------------------------------------- | -------------------------------------------------- |
| `repo` *(default)*           | Distribution package (`apt install ffmpeg`) | Almost always. Debian 13 ships 7.1.x.             |
| `github`                     | Prebuilt static build from BtbN/FFmpeg-Builds | Newer than the distro, or a specific release line |
| `minimal` / `medium` / `full`| Compiled from source                      | Only for codecs the above cannot provide           |

```bash
setup_ffmpeg                                    # distribution package
FFMPEG_TYPE="github" setup_ffmpeg               # latest master, GPL
FFMPEG_TYPE="github" FFMPEG_LICENSE="lgpl" setup_ffmpeg
FFMPEG_TYPE="github" FFMPEG_VERSION="n7.1" setup_ffmpeg
FFMPEG_TYPE="full" setup_ffmpeg                 # 20+ min build, avoid
```

Source builds use `--enable-gpl --enable-nonfree`. Those binaries must not be
redistributed - building them on the target host for its own use is fine, shipping
them is not. Use `repo` or `FFMPEG_LICENSE=lgpl` when an app requires LGPL FFmpeg.

### Helper Utilities

| Function/Variable             | Description                                            | Example                                   |
| ----------------------------- | ------------------------------------------------------ | ----------------------------------------- |
| `$LOCAL_IP`                   | Always available - contains the container's IP address | `echo "Access: http://${LOCAL_IP}:3000"`  |
| `ensure_dependencies`         | Checks/installs dependencies                           | `ensure_dependencies curl jq`             |
| `install_packages_with_retry` | APT install with retry                                 | `install_packages_with_retry nginx redis` |
| `create_backup`               | Backs up paths before an update                        | `create_backup /opt/app/.env`             |
| `restore_backup`              | Restores everything `create_backup` recorded           | `restore_backup`                          |
| `CLEAN_INSTALL_KEEP`          | Paths relative to the target that a `CLEAN_INSTALL=1` wipe leaves in place (see #19) | `CLEAN_INSTALL=1 CLEAN_INSTALL_KEEP="data uploads" fetch_and_deploy_gh_release ...` |
| `random_password [length]`    | Alphanumeric password of exactly `length` characters (default 24) | `ADMIN_PASS=$(random_password 16)` |

### Nginx Site Enablement

| Function            | Description                                                                                            | Example                    |
| -------------------- | ------------------------------------------------------------------------------------------------------- | --------------------------- |
| `nginx_enable_site`  | Symlinks a vhost from `sites-available` into `sites-enabled`, removes the default site, validates with `nginx -t`, and reloads nginx | `nginx_enable_site "appname"` |

The vhost content is always app-specific, so write it yourself with a heredoc into
`/etc/nginx/sites-available/<app>` — then hand the enable/reload dance to the helper
instead of repeating it by hand:

```bash
msg_info "Configuring Nginx"
cat <<EOF >/etc/nginx/sites-available/appname
server {
    listen 80;
    server_name _;

    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
    }
}
EOF
nginx_enable_site "appname"
msg_ok "Configured Nginx"
```

`nginx_enable_site` replaces the hand-rolled:

```bash
ln -sf /etc/nginx/sites-available/appname /etc/nginx/sites-enabled/appname
rm -f /etc/nginx/sites-enabled/default
systemctl restart nginx
```

Unlike most copies of that snippet scattered across the repo, it always runs `nginx -t`
before reloading — a bad vhost fails the install with a clear error instead of silently
leaving nginx down or serving stale config.

For PHP apps behind nginx, get the FPM socket path from `get_php_fpm_socket` instead of
hardcoding it in the vhost's `fastcgi_pass`:

```bash
PHP_SOCK=$(get_php_fpm_socket)
# use in the heredoc: fastcgi_pass unix:${PHP_SOCK};
```

---

## ❌ Anti-Patterns (NEVER use!)

### 1. Pointless Variables

```bash
# ❌ WRONG - unnecessary variables
APP_NAME="myapp"
APP_DIR="/opt/${APP_NAME}"
APP_USER="root"
APP_PORT="3000"
cd $APP_DIR

# ✅ CORRECT - use directly
cd /opt/myapp
```

### 2. Custom Download Logic

```bash
# ❌ WRONG - custom wget/curl logic
RELEASE=$(curl -s https://api.github.com/repos/owner/repo/releases/latest | jq -r '.tag_name')
wget https://github.com/owner/repo/archive/${RELEASE}.tar.gz
tar -xzf ${RELEASE}.tar.gz
mv repo-${RELEASE} /opt/myapp

# ✅ CORRECT - use our function
fetch_and_deploy_gh_release "myapp" "owner/repo"
```

### 3. Custom Version-Check Logic

```bash
# ❌ WRONG - custom version check
CURRENT=$(cat /opt/myapp/version.txt)
LATEST=$(curl -s https://api.github.com/repos/owner/repo/releases/latest | jq -r '.tag_name')
if [[ "$CURRENT" != "$LATEST" ]]; then
  # update...
fi

# ✅ CORRECT - use our function
if check_for_gh_release "myapp" "owner/repo"; then
  # update...
fi
```

### 4. Docker-based Installation

```bash
# ❌ WRONG - using Docker
docker pull myapp/myapp:latest
docker run -d --name myapp myapp/myapp:latest

# ✅ CORRECT - Bare-Metal Installation
fetch_and_deploy_gh_release "myapp" "owner/repo"
npm install && npm run build
```

### 5. Custom Runtime Installation

```bash
# ❌ WRONG - custom Node.js installation
curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
apt install -y nodejs

# ✅ CORRECT - use our function
NODE_VERSION="22" setup_nodejs
```

### 6. Redundant echo Statements

```bash
# ❌ WRONG - custom logging messages
echo "Installing dependencies..."
apt install -y curl
echo "Done!"

# ✅ CORRECT - use msg_info/msg_ok
msg_info "Installing Dependencies"
$STD apt install -y curl
msg_ok "Installed Dependencies"
```

### 7. Missing $STD Usage

```bash
# ❌ WRONG - apt without $STD
apt install -y nginx

# ✅ CORRECT - with $STD for silent output
$STD apt install -y nginx
```

### 8. Wrapping `tools.func` Functions in msg Blocks

```bash
# ❌ WRONG - tools.func functions have their own msg_info/msg_ok!
msg_info "Installing Node.js"
NODE_VERSION="22" setup_nodejs
msg_ok "Installed Node.js"

msg_info "Updating Application"
CLEAN_INSTALL=1 fetch_and_deploy_gh_release "appname" "owner/repo"
msg_ok "Updated Application"

# ✅ CORRECT - call directly without msg wrapper
NODE_VERSION="22" setup_nodejs

CLEAN_INSTALL=1 fetch_and_deploy_gh_release "appname" "owner/repo"
```

**Functions with built-in messages (NEVER wrap in msg blocks):**

- `fetch_and_deploy_gh_release`
- `check_for_gh_release`
- `setup_nodejs`
- `setup_postgresql` / `setup_postgresql_db`
- `setup_mariadb` / `setup_mariadb_db`
- `setup_mongodb`
- `setup_mysql`
- `setup_ruby`
- `setup_go`
- `setup_java`
- `setup_php`
- `setup_uv`
- `setup_rust`
- `setup_composer`
- `setup_ffmpeg`
- `setup_imagemagick`
- `setup_gs`
- `setup_adminer`
- `setup_hwaccel`
- `create_backup` / `restore_backup`

A helper called inside an open block hands the spinner back when it finishes, so
wrapping no longer hides the step — it still reports it twice. Call them directly.

### 9. Creating Unnecessary System Users

```bash
# ❌ WRONG - LXC containers run as root, no separate user needed
useradd -m -s /usr/bin/bash appuser
chown -R appuser:appuser /opt/appname
sudo -u appuser npm install

# ✅ CORRECT - run directly as root
cd /opt/appname
$STD npm install
```

### 10. Using `export` in .env Files

```bash
# ❌ WRONG - export is unnecessary in .env files
cat <<EOF >/opt/appname/.env
export DATABASE_URL=postgres://...
export SECRET_KEY=abc123
export NODE_ENV=production
EOF

# ✅ CORRECT - simple KEY=VALUE format (files are sourced with set -a)
cat <<EOF >/opt/appname/.env
DATABASE_URL=postgres://...
SECRET_KEY=abc123
NODE_ENV=production
EOF
```

### 11. Using External Shell Scripts

```bash
# ❌ WRONG - external script that gets executed
cat <<'EOF' >/opt/appname/install_script.sh
#!/bin/bash
cd /opt/appname
npm install
npm run build
EOF
chmod +x /opt/appname/install_script.sh
$STD bash /opt/appname/install_script.sh
rm -f /opt/appname/install_script.sh

# ✅ CORRECT - run commands directly
cd /opt/appname
$STD npm install
$STD npm run build
```

### 12. Using `sudo` in LXC Containers

```bash
# ❌ WRONG - sudo is unnecessary in LXC (already root)
sudo -u postgres psql -c "CREATE DATABASE mydb;"
sudo -u appuser npm install

# ✅ CORRECT - use functions or run directly as root
PG_DB_NAME="mydb" PG_DB_USER="myuser" setup_postgresql_db

cd /opt/appname
$STD npm install
```

### 13. Unnecessary `systemctl daemon-reload`

```bash
# ❌ WRONG - daemon-reload is only needed when MODIFYING existing services
cat <<EOF >/etc/systemd/system/appname.service
# ... service config ...
EOF
systemctl daemon-reload  # Unnecessary for new services!
systemctl enable -q --now appname

# ✅ CORRECT - new services don't need daemon-reload
cat <<EOF >/etc/systemd/system/appname.service
# ... service config ...
EOF
systemctl enable -q --now appname
```

### 14. Creating Custom Credentials Files

```bash
# ❌ WRONG - custom credentials file is not part of the standard template
msg_info "Saving Credentials"
cat <<EOF >~/appname.creds
Database User: ${DB_USER}
Database Pass: ${DB_PASS}
EOF
msg_ok "Saved Credentials"

# ✅ CORRECT - credentials are stored in .env or shown in final message only
# The .env file contains credentials, no need for separate file
```

### 15. Wrong Footer Pattern

```bash
# ❌ WRONG - old cleanup pattern with msg blocks
motd_ssh
customize

msg_info "Cleaning up"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"

# ✅ CORRECT - use cleanup_lxc function
motd_ssh
customize
cleanup_lxc
```

### 16. Manual Database Creation Instead of Functions

```bash
# ❌ WRONG - manual database creation
DB_USER="myuser"
DB_PASS=$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | cut -c1-13)
$STD sudo -u postgres psql -c "CREATE ROLE $DB_USER WITH LOGIN PASSWORD '$DB_PASS';"
$STD sudo -u postgres psql -c "CREATE DATABASE mydb WITH OWNER $DB_USER;"
$STD sudo -u postgres psql -d mydb -c "CREATE EXTENSION IF NOT EXISTS postgis;"

# ✅ CORRECT - use setup_postgresql_db function
# This sets PG_DB_USER, PG_DB_PASS, PG_DB_NAME automatically
PG_DB_NAME="mydb" PG_DB_USER="myuser" PG_DB_EXTENSIONS="postgis" setup_postgresql_db
```

### 18. Hardcoded Versions for External Tools

```bash
# ❌ WRONG - hardcoded versions that will become outdated
RESTIC_VERSION="0.18.1"
RCLONE_VERSION="1.73.0"
curl -L -o restic.bz2 "https://github.com/restic/restic/releases/download/v${RESTIC_VERSION}/restic_${RESTIC_VERSION}_linux_amd64.bz2"

# ✅ CORRECT - use fetch_and_deploy_gh_release (always fetches latest)
fetch_and_deploy_gh_release "restic" "restic/restic" "singlefile" "latest" "/usr/local/bin" "restic_*_linux_amd64.bz2"

# If you need the version number later, read from the version file:
RES_VERSION=$(cat ~/.restic)
# Or use get_latest_github_release:
VERSION=$(get_latest_github_release "restic/restic")
```

### 19. Hand-rolled Backups in Update Scripts

```bash
# ❌ WRONG - manual cp/mv dance (and /tmp can be cleared by the system)
msg_info "Backing up Configuration"
cp /opt/appname/.env /tmp/appname.env.bak
msg_ok "Backed up Configuration"
# ... update ...
cp /tmp/appname.env.bak /opt/appname/.env

# ✅ CORRECT - use the helpers (they bring their own msg_info/msg_ok)
create_backup /opt/appname/.env
CLEAN_INSTALL=1 CLEAN_INSTALL_KEEP="data uploads" fetch_and_deploy_gh_release "appname" "owner/repo" "tarball"
restore_backup
```

`create_backup` stores into `/opt/<NSAPP>.backup` (override with `BACKUP_DIR`),
records a manifest so `restore_backup` needs no arguments, uses `cp -a` so
permissions survive, skips re-backing-up on a retry so the last-known-good copy
is kept, and aborts the update if the backup itself fails.

Directories inside the deploy target — uploads, storage, databases — go into
`CLEAN_INSTALL_KEEP` instead. They are moved aside and back, not copied, so an
update needs neither the time nor the free space for a second copy, and nested
paths and symlinks survive as they are. Two limits decide which mechanism a path
gets:

- Kept paths are back **before** the release is unpacked, so anything the release
  ships under the same name overwrites them. A path upstream ships a default for
  (a `config.yml`, a `config/` with samples) belongs in `create_backup`, which
  restores after the deploy. Check the release tree before keeping a path.
- A build that empties its output directory (`dist/`, `build/`) deletes what was
  kept there.

### 20. Using "(Patience)" in msg_info by Default

```bash
# ❌ WRONG - "(Patience)" should not be a default label
msg_info "Building Application (Patience)"
$STD npm run build
msg_ok "Built Application"

# ✅ CORRECT - use a plain label; only add (Patience) if the build truly takes 10+ minutes
msg_info "Building Application"
$STD npm run build
msg_ok "Built Application"
```

### 21. Writing Files Without Heredocs

```bash
# ❌ WRONG - echo / printf / tee
echo "# Config" > /opt/app/config.yml
echo "port: 3000" >> /opt/app/config.yml

printf "# Config\nport: 3000\n" > /opt/app/config.yml
cat config.yml | tee /opt/app/config.yml
```

```bash
# ✅ CORRECT - always use a single heredoc
cat <<EOF >/opt/app/config.yml
# Config
port: 3000
EOF
```

### 22. Using `apt-get` Instead of `apt`

```bash
# ❌ WRONG - apt-get is not the project convention
$STD apt-get install -y nginx
$STD apt-get update

# ✅ CORRECT - always use apt (consistent with tools.func)
$STD apt install -y nginx
$STD apt update
```

### 23. Listing Core/Pre-installed Packages as Dependencies

```bash
# ❌ WRONG - curl is already installed by _bootstrap() in install.func
# sudo is already available in LXC, mc is not a dependency
msg_info "Installing Dependencies"
$STD apt install -y \
  curl \
  sudo \
  mc \
  fuse3
msg_ok "Installed Dependencies"

# ✅ CORRECT - only list packages that are actually needed by the application
msg_info "Installing Dependencies"
$STD apt install -y fuse3
msg_ok "Installed Dependencies"
```

**Packages that must NOT be listed as dependencies (already available):**

- `curl` — installed by `_bootstrap()` in `install.func`
- `sudo` — base LXC package (and scripts run as root anyway)
- `wget` — base Debian LXC package
- `gnupg` / `gpg` — base Debian package
- `ca-certificates` — base Debian package
- `apt-transport-https` — obsolete on Debian 12+
- `jq` — auto-installed by `ensure_dependencies` in `tools.func` when needed
- `mc` — not a dependency, personal preference tool

**When to omit the dependency block entirely:** If the app only needs packages provided by `setup_*` helpers (e.g., Node.js, PostgreSQL, Go) or is a prebuilt binary with no native deps, skip the "Installing Dependencies" block completely.

### 24. Prompting Without an Escape Hatch

A `read` that always fires cannot be answered in advance, so the script can only
ever be installed by hand. Read the variable first and prompt only when it is
unset:

```bash
# ❌ WRONG - the environment is overwritten before it is ever read.
# read assigns an empty string when stdin is closed, so the :- fallback
# fires and whatever the caller passed is gone.
read -rp "${TAB3}Admin username: " admin_user
admin_user="${admin_user:-admin}"

# ✅ CORRECT
if [[ -z "${var_admin_user:-}" ]]; then
  read -rp "${TAB3}Admin username: " var_admin_user
fi
var_admin_user="${var_admin_user:-admin}"
```

Name it `var_<something>` — the same namespace the container variables use —
export it from `ct/<app>.sh`, and declare it in the JSON `app_vars`. All three
are needed: without the export it never reaches the container, and without the
declaration the website cannot offer it as a field.

`install/forgejo-runner-install.sh` and `install/pangolin-install.sh` follow
this.

**Built-in alternative:** `core.func` also ships `prompt_input_required "<message>" "<fallback>" [timeout] ["var_x"]`,
`prompt_input`, `prompt_confirm`, and `prompt_select` — they wrap this exact
env-var-first check plus unattended-mode detection (`is_unattended`), a TTY check, and a
timeout-with-fallback, and (for `prompt_input_required`) track every field that fell back
in `MISSING_REQUIRED_VALUES` for an end-of-script summary. Prefer them in new scripts
over the raw `read -rp` pattern above; the manual pattern still works and existing
scripts using it are not wrong.

```bash
var_admin_user=$(prompt_input_required "Admin username:" "admin" 60 "var_admin_user")
```

### 25. Hand-rolled Nginx Site Enablement

```bash
# ❌ WRONG - repeating the enable/reload dance by hand
ln -sf /etc/nginx/sites-available/appname /etc/nginx/sites-enabled/appname
rm -f /etc/nginx/sites-enabled/default
systemctl restart nginx

# ✅ CORRECT - use the helper (symlinks, drops default, validates, reloads)
nginx_enable_site "appname"
```

Writing the vhost itself still needs a heredoc into `sites-available` — only the
enable/reload part is what `nginx_enable_site` replaces.

### 26. Comments

```bash
# ❌ WRONG - banner separators and comments that just repeat the next line
# ==============================================================================
# CONFIGURATION
# ==============================================================================
APP="AppName"

# Enable error handling
set -Eeuo pipefail
trap 'error_handler' ERR

# Wait for API to start
sleep 5

# Create credentials file
cat >"${CONFIG_DIR}/INSTALLATION_INFO.txt" <<EOF
...
EOF

# ✅ CORRECT - no comments
APP="AppName"

set -Eeuo pipefail
trap 'error_handler' ERR

sleep 5

cat >"${CONFIG_DIR}/INSTALLATION_INFO.txt" <<EOF
...
EOF
```

`ct/` and `install/` scripts carry no comments besides the header. A line that would
look like a mistake without one may get a single short comment, and that stays the
exception: not one per workaround, never two-line explanations. Why you chose something
goes into the PR description, once. No `====`/`----`/`####` banners; `msg_info` blocks
already divide the script.

### 27. Hand-rolled `git clone`/`git pull` for Tag-only or Rolling-release Apps

```bash
# ❌ WRONG - hand-rolled git clone/pull because the repo has no GitHub Releases
git clone https://github.com/owner/repo /opt/appname
cd /opt/appname && git pull

# ✅ CORRECT - repo publishes tags but no Releases
fetch_and_deploy_gh_tag "appname" "owner/repo"
# ...
if check_for_gh_tag "appname" "owner/repo"; then
  CLEAN_INSTALL=1 fetch_and_deploy_gh_tag "appname" "owner/repo"
fi

# ✅ CORRECT - repo publishes neither releases nor tags (deployed from a branch)
fetch_and_deploy_gh_branch "appname" "owner/repo" "main"
# ...
if check_for_gh_branch "appname" "owner/repo" "main"; then
  CLEAN_INSTALL=1 fetch_and_deploy_gh_branch "appname" "owner/repo" "main"
fi
```

`fetch_and_deploy_gh_release`/`check_for_gh_release` are for repos with GitHub Releases.
When a repo only tags commits, use the `_gh_tag` pair; when it has neither, use the
`_gh_branch` pair (it shallow-clones and fast-forwards, tracking the short SHA in
`~/.<app>` the same way the others track a version).

---

### 28. Defining Your Own Functions

```bash
# ❌ WRONG - helper functions in an install script
run_nb() {
  runuser -u nautobot -- /opt/nautobot/bin/nautobot-server "$@"
}
run_nb migrate
run_nb collectstatic --noinput

# ✅ CORRECT - write the commands out
$STD /opt/nautobot/bin/nautobot-server migrate
$STD /opt/nautobot/bin/nautobot-server collectstatic --noinput
```

The only function in a CT script is `update_script()`. Install scripts define none.
A wrapper you call twice is not worth the indirection; a wrapper you call once is noise.

### 29. Bare-Metal Python Instead of `uv`

```bash
# ❌ WRONG - venv + pip, and python3-pip as a dependency
$STD apt install -y python3-pip python3-venv
python3 -m venv /opt/app
$STD /opt/app/bin/pip install --upgrade pip wheel
$STD /opt/app/bin/pip install myapp

# ✅ CORRECT - uv, with the Python version the project asks for
PYTHON_VERSION="3.12" setup_uv
$STD uv venv /opt/app/.venv
$STD uv pip install -p /opt/app/.venv/bin/python myapp
```

With a lockfile (`uv.lock`) in the project, use `uv sync` instead:

```bash
cd /opt/app
$STD uv sync --locked --no-editable --no-install-project
```

`setup_uv` reads **`PYTHON_VERSION`**. `UV_PYTHON` is ignored — it does nothing.

### 30. Placeholder Names in User-Facing Messages

```bash
# ❌ WRONG - the user sees a variable name, or a generic word
msg_info "Stopping ${APPLICATION}"
msg_info "Stopping $APP"
msg_info "Updating Application"

# ✅ CORRECT - the tool's name, written out
msg_info "Stopping Nautobot"
msg_ok "Stopped Nautobot"
```

Same for service names, paths and the `.env`: `/opt/nautobot`, `nautobot.service`.
Never `${APPLICATION}` or `${APP_NAME}` in a submitted script.

### 31. Creating a Dedicated Service User Because Upstream Says So

```bash
# ❌ WRONG - upstream's docs assume a shared server, not a single-app LXC
useradd --system --shell /bin/bash --home-dir /opt/nautobot nautobot
$STD runuser -u nautobot -- /opt/nautobot/bin/nautobot-server migrate

# ✅ CORRECT - the container is the isolation boundary; run as root
$STD /opt/nautobot/bin/nautobot-server migrate
```

Upstream install guides target multi-tenant hosts. An LXC runs one application.
`runuser`, `su -c` and `sudo -u` do not belong in these scripts (see also #9, #12).

### 32. The Engine Comment Block Above `_cs_boot`

```bash
# ❌ WRONG - these three lines must not be in a ct/ script
#!/usr/bin/env bash
# Engine comes from community-scripts/core; this repo only ships the scripts.
# Local checkout wins (COMMUNITY_SCRIPTS_CORE_DIR, else a sibling ../core), so a
# fork/branch of core can be tested without touching this file.
_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-...}"

# ✅ CORRECT - shebang, the scripts base, then straight into the bootstrap
#!/usr/bin/env bash
_CS_DEFAULT_URL="https://raw.githubusercontent.com/community-scripts/DevScripts/main"
_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-...}"
```

### 33. Hand-rolled Password Generators

```bash
# ❌ WRONG - returns fewer characters than asked for (the filter runs after the
# length is fixed), and the | cut variant puts / and + into the password
DB_PASS=$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | head -c13)
ADMIN_PASS=$(openssl rand -base64 18 | cut -c1-13)

# ✅ CORRECT - alphanumeric, exactly the requested length
DB_PASS=$(random_password 13)
ADMIN_PASS=$(random_password)
```

Hex tokens stay `openssl rand -hex 32`. A secret the application decodes as
base64, or that upstream documents as `openssl rand -base64 32`, stays as it is.

### 34. Unbalanced msg Blocks

Every `msg_info` opens a block that exactly one `msg_ok` (or a `msg_error` that
ends the script) closes. A block left open comes back as a spinner after every
later `msg_ok`.

```bash
# ❌ WRONG - a completion reported with msg_info, a notice opened as a block,
# a spinner running under a prompt
msg_info "Stopping Service"
systemctl stop appname
msg_info "Stopped Service"

msg_info "This update clears the configuration."

msg_info "Installing Agent"
stop_spinner
read -r -p "${TAB3}Server URL: " server_url

# ✅ CORRECT
msg_info "Stopping Service"
systemctl stop appname
msg_ok "Stopped Service"

msg_warn "This update clears the configuration."

read -r -p "${TAB3}Server URL: " server_url
msg_info "Installing Agent"
```

Notices are `msg_warn`, or `echo -e "${INFO}${YW}...${CL}"` when nothing is
wrong. Ask before opening a block, never inside one, and never call
`stop_spinner` directly.

### 35. Re-tuning Timeouts the Helpers Already Set

```bash
# ❌ WRONG - lowers what the helper set
PYTHON_VERSION="3.12" setup_uv
export UV_HTTP_TIMEOUT=300

# ✅ CORRECT - setup_uv exports UV_HTTP_TIMEOUT=600
PYTHON_VERSION="3.12" setup_uv
```

`setup_uv` (`UV_HTTP_TIMEOUT`), `setup_composer` (`process-timeout`),
`setup_rust` (cargo `net.retry`) and the pnpm/yarn setup already raise the
network limits. Override one only for a measured reason, upward.

---

### 36. A Closing Block That Explains the App

```bash
# ❌ WRONG - branches, pct exec and a setup tutorial after description
TS_NAME=""
[[ "$var_tailscale" == "yes" ]] && TS_NAME=$(pct exec "$CTID" -- tailscale status --json | jq -r '.Self.DNSName')
if [[ -n "$TS_NAME" ]]; then
  echo -e "${INFO}${YW} On your tailnet:${CL}"
  ...
fi
echo -e "${INFO}${YW} Add it to Claude Code (token from the .env file):${CL}"
echo -e "${TAB}claude mcp add --transport http ..."

# ✅ CORRECT - the standard three lines, at most one more
msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW}Access it using the following URL:${CL}"
echo -e "${GATEWAY}${BGN}http://${IP}:PORT${CL}"
```

One extra line for a second port or where the credentials are is fine. Everything else
the user needs goes into the JSON `notes` (see "Notes Format").

---

## 📝 Important Rules

### Variable Declarations (CT Script)

```bash
# Standard declarations (ALWAYS present)
APP="AppName"
var_tags="${var_tags:-tag1;tag2}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-8}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_unprivileged="${var_unprivileged:-1}"
```

**Optional declarations**

| Variable      | Values                   | Meaning                                                      |
| ------------- | ------------------------ | ------------------------------------------------------------ |
| `var_gpu`     | `yes` / `no`             | Offer GPU passthrough. Set for transcoding and AI workloads. |
| `var_arm64`   | `yes` / `no` / *(unset)* | arm64 support — see below.                                   |
| `var_testurl` | an `https://` URL        | Where feedback for this script goes — see below.             |

`var_testurl` names the thread collecting feedback for a script that is still
being tested. Create the issue, then point the script at it:

```bash
var_testurl="${var_testurl:-https://github.com/community-scripts/DevScripts/issues/2135}"
```

The container then asks for feedback on every login, in its Proxmox description,
through a `testing` tag, and on the last line of the install — always with that
one link, so a tester never has to work out where to report.

Leaving it out changes nothing: a script here still gets the generic development
warning. Only `https://` URLs are accepted, and a rejected value falls back to
that generic warning rather than failing the build. It is not settable from a
`.vars` file, because it describes the script rather than the user's
preferences.

Keep it set if the script is promoted to ProxmoxVE while feedback is still
wanted — the request follows the script and stops naming DevScripts.

`var_arm64` has three states. **Only claim `yes` when it has actually been run on
arm64** — the mere existence of an arm64 artifact is not verification:

- `yes` — verified working, proceeds silently
- `no` — known broken (x64-only artifact, x86 dependency, CUDA), aborts
- *unset* — never tried. The user is told so and asked whether to attempt it
  anyway, with a pointer to report the result. Aborts non-interactively.

Leave the line in place but commented out, so the option stays discoverable
where someone would look for it:

```bash
#var_arm64="${var_arm64:-no}" # unset = ask the user; set yes/no only when verified
```

When setting it to `no`, state the reason next to it — otherwise the value
degrades back into "nobody checked".

**Application settings**

Anything the install script should be able to receive up front is declared here
too, and **must be exported** — `lxc-attach` carries the caller's environment,
but only what was exported:

```bash
export var_admin_user="${var_admin_user:-}"
export var_admin_token="${var_admin_token:-}"
```

Without the export the variable stays on the host, the install script finds it
empty, and an unattended run stops at a prompt inside the container where
nobody can answer it. Declare the same names in the JSON `app_vars` so the
website can offer them as fields.

If a value is required, fail early — checking it in the CT script costs the
user seconds, checking it inside the container costs a full build:

```bash
if [[ -n "${mode:-}" ]]; then
  if [[ -z "${var_admin_token:-}" ]]; then
    msg_error "var_admin_token is required for unattended installs."
    exit 1
  fi
fi
```

### Update-Script Pattern

```bash
function update_script() {
  header_info
  check_container_storage
  check_container_resources

  # 1. Check if installation exists
  if [[ ! -d /opt/appname ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  # 2. Check for update
  if check_for_gh_release "appname" "owner/repo"; then
    # 3. Stop service
    msg_info "Stopping Service"
    systemctl stop appname
    msg_ok "Stopped Service"

    # 4. Backup config files (if present) - has its own messages, do not wrap
    create_backup /opt/appname/.env

    # 5. Perform clean install; data directories inside the target stay in place
    CLEAN_INSTALL=1 CLEAN_INSTALL_KEEP="data" fetch_and_deploy_gh_release "appname" "owner/repo" "tarball"

    # 6. Restore BEFORE any build step that reads the config
    restore_backup

    # 7. Rebuild (if needed)
    cd /opt/appname
    $STD npm install
    $STD npm run build

    # 8. Start service
    msg_info "Starting Service"
    systemctl start appname
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit  # IMPORTANT: Always end with exit!
}
```

### Systemd Service Pattern

```bash
msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/appname.service
[Unit]
Description=AppName Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/appname
Environment=NODE_ENV=production
ExecStart=/usr/bin/node /opt/appname/server.js
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now appname
msg_ok "Created Service"
```

### Installation Script Footer

```bash
# ALWAYS at the end of the install script:
motd_ssh
customize
cleanup_lxc
```

---

## 🔍 Checklist Before PR Creation

- [ ] No Docker installation used
- [ ] `fetch_and_deploy_gh_release` used for GitHub releases (with explicit mode like `"tarball"`)
- [ ] `check_for_gh_release` used for update checks
- [ ] `setup_*` functions used for runtimes (nodejs, postgresql, etc.)
- [ ] **`tools.func` functions NOT wrapped in msg_info/msg_ok blocks**
- [ ] No redundant variables
- [ ] No hardcoded versions for external tools (use `fetch_and_deploy_gh_release` or `get_latest_github_release`)
- [ ] `$STD` before all apt/npm/build commands
- [ ] `apt` used (NOT `apt-get`) — consistent with `tools.func`
- [ ] No core packages listed as dependencies (`curl`, `sudo`, `wget`, `jq`, `mc` are pre-installed)
- [ ] `msg_info`/`msg_ok`/`msg_error` for logging (only for custom code)
- [ ] Correct script structure followed
- [ ] Update function present and functional
- [ ] Data backup implemented in update function (backups go to `/opt`, NOT `/tmp`)
- [ ] Data directories inside the deploy target kept with `CLEAN_INSTALL_KEEP` — only paths the release does not ship
- [ ] Passwords via `random_password`, no `openssl rand -base64 | tr | head` pipelines
- [ ] Every `msg_info` closed by exactly one `msg_ok`; notices via `msg_warn`; no prompt inside a block, no `stop_spinner`
- [ ] No `UV_HTTP_TIMEOUT`/composer/cargo timeouts set by hand
- [ ] `motd_ssh`, `customize`, `cleanup_lxc` at the end
- [ ] No custom download/version-check logic
- [ ] No default `(Patience)` text in msg_info labels
- [ ] Nginx sites enabled via `nginx_enable_site`, not hand-rolled `ln -sf`/`rm -f`/`systemctl restart`
- [ ] No comments besides the header (a rare one-liner where the code would look wrong)
- [ ] Closing block: the standard three lines, at most one more
- [ ] Tag-only or releaseless (branch-tracking) repos use `fetch_and_deploy_gh_tag`/`fetch_and_deploy_gh_branch`, not hand-rolled `git clone`/`git pull`
- [ ] JSON metadata file created in `json/<appname>.json`
- [ ] Upstream `Dockerfile`/`docker-compose.yml`/`.env.example` read, and the source named in one line of the PR description
- [ ] **No functions defined** beyond `update_script()` in the CT script
- [ ] Python uses `setup_uv` + `uv` — no `venv`, no `pip`, no `python3-pip` dependency
- [ ] `PYTHON_VERSION` (not `UV_PYTHON`) passed to `setup_uv`
- [ ] Every user-facing message names the application, no `${APPLICATION}`/`$APP` placeholders
- [ ] No `useradd`/`runuser`/`su -c` — the script runs as root
- [ ] No engine comment block above `_cs_boot` in the CT script
- [ ] Line 2 of the CT script pins `_CS_DEFAULT_URL` to DevScripts
- [ ] `var_arm64` decided (yes/no) with the reason in the PR, or explicitly left to the user
- [ ] Alpine variant, if any, follows Shape A or Shape B — never a duplicated script
- [ ] `setup_*`/`update_*` defined for every OS family the script claims to support
- [ ] No `systemctl`/`.service` inside an Alpine branch — OpenRC only
- [ ] PR description: two to five sentences, nothing outside the template's sections

---

## 📖 Reference: Good Example (Journiv)

Read both files end to end before writing your own. They are short on purpose.

### CT Script: [ct/journiv.sh](https://github.com/community-scripts/ProxmoxVE/blob/main/ct/journiv.sh)

- No engine comment block above `_cs_boot`
- `check_for_gh_release` for the version check
- One function only: `update_script()`
- Every message names Journiv

### Install Script: [install/journiv-install.sh](https://github.com/community-scripts/ProxmoxVE/blob/main/install/journiv-install.sh)

- 131 lines, **zero** functions of its own, one comment besides the header
- `setup_postgresql` / `setup_postgresql_db` / `setup_uv` instead of hand-rolled setup
- `uv sync` for Python, no `venv`, no `pip`
- Correct footer with `motd_ssh`, `customize`, `cleanup_lxc`

---

## � JSON Metadata Files

Every application requires a JSON metadata file in `json/<appname>.json`.

### JSON Structure

```json
{
  "name": "AppName",
  "slug": "appname",
  "categories": [1],
  "date_created": "2026-01-16",
  "type": "ct",
  "updateable": true,
  "privileged": false,
  "interface_port": 3000,
  "documentation": "https://docs.appname.com/",
  "website": "https://appname.com/",
  "repository": "https://github.com/owner/appname",
  "architectures": ["amd64"],
  "platforms": ["pve"],
  "logo": "https://cdn.jsdelivr.net/gh/selfhst/icons@main/webp/appname.webp",
  "description": "Short description of the application and its purpose.",
  "install_methods": [
    {
      "type": "default",
      "script": "ct/appname.sh",
      "config_path": "/opt/appname/.env",
      "resources": {
        "cpu": 2,
        "ram": 2048,
        "hdd": 8,
        "os": "Debian",
        "version": "13"
      }
    }
  ],
  "default_credentials": {
    "username": null,
    "password": null
  },
  "notes": []
}
```

### Required Fields

| Field                 | Type    | Description                                        |
| --------------------- | ------- | -------------------------------------------------- |
| `name`                | string  | Display name of the application                    |
| `slug`                | string  | Lowercase, no spaces, used for filenames           |
| `categories`          | array   | Category ID(s) - see category list below           |
| `date_created`        | string  | Creation date (YYYY-MM-DD)                         |
| `type`                | string  | `ct` for container, `vm` for virtual machine       |
| `updateable`          | boolean | Whether update_script is implemented               |
| `privileged`          | boolean | Whether container needs privileged mode            |
| `interface_port`      | number  | Primary web interface port (or `null`)             |
| `documentation`       | string  | Link to official docs                              |
| `website`             | string  | Link to official website                           |
| `repository`          | string  | Upstream repository as a full URL. A bare `owner/repo` could only ever mean GitHub, and the release sync also reads GitLab, Gitea, Forgejo and Codeberg |
| `architectures`       | array   | Must agree with `var_arm64` in the CT script — that is the one `arch_check` obeys. `yes` → `["amd64", "arm64"]`, `no` → `["amd64"]`, unset → omit the field. The site reads an absent field as amd64, so "known broken" and "never tried" look the same there; only `var_arm64` keeps them apart |
| `logo`                | string  | URL to application logo (preferably selfhst icons) |
| `description`         | string  | Brief description of the application               |
| `install_methods`     | array   | Installation configurations                        |
| `default_credentials` | object  | Default username/password (or null)                |
| `notes`               | array   | Additional notes/warnings                          |

### Optional Fields

| Field       | Type  | Description                                                                 |
| ----------- | ----- | --------------------------------------------------------------------------- |
| `platforms` | array | `["pve"]`, `["incus"]` or both. Omit to mean Proxmox VE                      |
| `app_vars`  | array | Values the install script accepts up front, so a deployment can run unattended |

`app_vars` describes what the script already reads from the environment. Name
each one `var_<something>`, read it before prompting, and export it from
`ct/<app>.sh` — without the export it never reaches the container:

```bash
# ct/appname.sh
export var_admin_user="${var_admin_user:-}"

# install/appname-install.sh
if [[ -z "${var_admin_user:-}" ]]; then
  read -r -p "${TAB3}Admin username: " var_admin_user
fi
var_admin_user="${var_admin_user:-admin}"
```

```json
"app_vars": [
  { "name": "var_admin_user", "label": "Admin Username", "type": "text", "default": "admin" },
  { "name": "var_admin_pass", "label": "Admin Password", "type": "password", "secret": true, "required": true }
]
```

`type` is one of `text`, `password`, `number`, `boolean` (emits `yes`/`no`) or
`select` (with `options`). A declaration whose `name` the script never reads
produces a generated command that looks right and changes nothing.

### Categories

| ID  | Category                  |
| --- | ------------------------- |
| 0   | Miscellaneous             |
| 1   | Proxmox & Virtualization  |
| 2   | Operating Systems         |
| 3   | Containers & Docker       |
| 4   | Network & Firewall        |
| 5   | Adblock & DNS             |
| 6   | Authentication & Security |
| 7   | Backup & Recovery         |
| 8   | Databases                 |
| 9   | Monitoring & Analytics    |
| 10  | Dashboards & Frontends    |
| 11  | Files & Downloads         |
| 12  | Documents & Notes         |
| 13  | Media & Streaming         |
| 14  | \*Arr Suite               |
| 15  | NVR & Cameras             |
| 16  | IoT & Smart Home          |
| 17  | ZigBee, Z-Wave & Matter   |
| 18  | MQTT & Messaging          |
| 19  | Automation & Scheduling   |
| 20  | AI / Coding & Dev-Tools   |
| 21  | Webservers & Proxies      |
| 22  | Bots & ChatOps            |
| 23  | Finance & Budgeting       |
| 24  | Gaming & Leisure          |
| 25  | Business & ERP            |

### Notes Format

```json
"notes": [
    {
        "text": "Change the default password after first login!",
        "type": "warning"
    },
    {
        "text": "Requires at least 4GB RAM for optimal performance.",
        "type": "info"
    }
]
```

**Note types:** `info`, `warning`, `error`

**Keep notes short.** The script page shows every note; a wall of text gets skipped.

- At most 3 notes, one or two short sentences each (about 200 characters).
- Only what a user has to know or do: how to get the first login, a required manual step (API key, reverse proxy, HTTPS), a real risk (open signup, no auth).
- Leave out what the script installs, build times, RAM measurements, update mechanics, upstream bugs, data paths the user never has to touch, and anything the description or the CT script's final message already says.
- `description` says what the app is and what it can do in 2–3 sentences (up to about 400 characters), not what the script installs.

### Examples with Credentials

```json
"default_credentials": {
    "username": "admin",
    "password": "admin"
}
```

Or no credentials:

```json
"default_credentials": {
    "username": null,
    "password": null
}
```

---

## �💡 Tips for AI Assistants

1. **Search `tools.func` first** before implementing custom solutions
2. **Use existing scripts as reference** (e.g., `linkwarden-install.sh`, `homarr-install.sh`)
3. **Ask when uncertain** instead of introducing wrong patterns
4. **Consistency > Creativity** - follow established patterns
5. **Test local variables** - use `${VAR:-default}` pattern for optional values
6. **Check eligibility before scaffolding a new app** - new-script PRs must meet the
   Application Requirements in [`.github/pull_request_template.md`](.github/pull_request_template.md):
   **1,000+ stars** (GitHub, GitLab, Gitea/Forgejo, or Codeberg), **6+ months old**,
   **actively maintained**, and **official release tarballs published**. Look up the
   real star count on the app's forge and flag the user immediately if it falls short,
   before generating any files.
7. **Alpine is supported transparently** - setting `var_os="alpine"` routes the same
   helper function names (`fetch_and_deploy_gh_release`, `check_for_gh_release`,
   `setup_yq`, `setup_adminer`, `setup_uv`, `setup_java`, `setup_go`, `setup_composer`,
   ...) through Alpine-specific implementations. Call the same functions regardless of
   `var_os` — never branch script logic on the OS yourself for things these functions
   already handle.

---

## 📝 Pull Request Text and Review

Reviewers read the diff, not an essay about it.

- Fill in the template. No extra sections, headings, tables or decision lists.
- Description: two to five sentences. What the app is, what deviates from the standard
  pattern (one line each), how you tested it (one line), and the model and reasoning
  level if an agent wrote it. Nothing the diff or this file already says.
- A review suggestion is applied exactly as written ("Commit suggestion" on GitHub, or
  the same text by hand), then its thread is resolved. Do not regenerate the file to
  answer a review.
- Replies to review comments: one or two sentences. Resolve only what you changed.

---

## 📚 Further Documentation

- [CONTRIBUTING.md](docs/contribution/CONTRIBUTING.md) - General contribution guidelines
- [GUIDE.md](docs/contribution/GUIDE.md) - Detailed developer documentation
- [TECHNICAL_REFERENCE.md](docs/TECHNICAL_REFERENCE.md) - Technical details
- [EXIT_CODES.md](docs/EXIT_CODES.md) - Exit code reference
