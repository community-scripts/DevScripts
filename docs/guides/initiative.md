# Test Initiative on Proxmox

This test installer is proposed for
[DevScripts](https://github.com/community-scripts/DevScripts), the required
testing stage before a new script can reach ProxmoxVE. It is not an accepted
Community Script. Initiative has 192 stars as of 2026-10-30, below DevScripts'
600-star requirement and the ProxmoxVE script-request form's 1,000-star
requirement. Consideration requires a maintainer exception; neither threshold
is claimed to be met.

Record test results in the
[DevScripts testing issue](https://github.com/community-scripts/DevScripts/issues/2483).
The [ProxmoxVE discussion](https://github.com/community-scripts/ProxmoxVE/discussions/18319)
requests the adoption exception; the
[personal acceptance issue](https://github.com/Dunky13/ProxmoxVED/issues/1)
preserves the earlier testing history.

## Create the container

Run these commands as root in the **Proxmox host shell**, not in an existing
container:

```bash
export COMMUNITY_SCRIPTS_URL=https://raw.githubusercontent.com/Dunky13/ProxmoxVED/refs/heads/feat/initiative
dev_mode=keep bash -c "$(curl -fsSL "$COMMUNITY_SCRIPTS_URL/ct/initiative.sh")"
```

Keep the `export`: the engine needs it to find the matching installer in the
fork, and the container's `update` command remembers this source. Merely
downloading `ct/initiative.sh` from the fork does not select the fork's
`install/initiative-install.sh`.

The standard Community Scripts wizard creates an **unprivileged Debian 13 LXC**
with **2 CPU cores, 2048 MiB RAM and an 8 GiB disk**. Choose its bridge, storage,
container ID and network settings in the wizard. These are initial test defaults,
not measured capacity guarantees. Leave the OS on Debian 13: the server package
requires its Python 3.13 ABI. The `keep` flag preserves a failed container for
diagnosis. Do not add the `trace` flag when collecting logs containing secrets.

Open **`https://CONTAINER-IP`**, accept the self-signed certificate and create
your first account immediately. That account becomes the owner. Subsequent
public registration is disabled; there is no default username or password.
Keep the new instance on your private network while completing this step.

## What it installs

- The official `initiative-server` Debian release package, after checking its
  matching architecture-specific SHA-256 manifest. It does not install the
  Electron desktop client or rebuild the Python/browser dependencies.
- PostgreSQL 17 from Debian's repository, with a generated database password.
- The package's `initiative-server.service`, running as the package's
  unprivileged `initiative` account.
- Nginx on HTTPS port 443, with HTTP port 80 redirected to HTTPS and WebSocket
  proxying. Initiative listens on loopback port 8173. HTTPS is needed by browser
  crypto features even when accessing the application by LAN address.

The installer uses Community Scripts' setup, release, certificate and nginx
helpers. The native package already contains its Python environment, so there
is no `setup_uv`, pip or Node.js install. The database owner has the privileges
needed for initial RLS-role provisioning and the LEAKPROOF search operator.
Initiative disposes of that bootstrap connection before serving requests and
uses its separate application roles for runtime access.

## Configuration and updates

Configuration and generated secrets live in `/etc/initiative/server.env`, owned
by `root:initiative`, mode `0640`. Uploads live in
`/var/lib/initiative/uploads`. Preserve `SECRET_KEY`: it also protects encrypted
data. The installer refuses to overwrite an existing configuration.

After changing the IP or using a domain, update `APP_URL` in the configuration
and run:

```bash
systemctl restart initiative-server
```

Use a trusted HTTPS reverse proxy and certificate for a public domain. The
self-signed certificate is created for the container's original address.

Take a Proxmox backup before upgrading. Then run **inside the container**:

```bash
update
```

The updater checks for a newer release, downloads and verifies it before stopping
anything, then stops Initiative and PostgreSQL. It copies the local configuration,
uploads, PostgreSQL configuration and **stopped database cluster, including
roles**, into a private `/opt/initiative-backup.*` directory. It starts PostgreSQL,
installs the verified package with existing configuration preserved, and explicitly
reloads the systemd unit before starting Initiative. Readiness must pass before the
installed-version record moves forward. Backup directories remain for manual
recovery and consume disk space.

Initiative can be ready while reporting `"status":"degraded"`: the three
database checks must be `"ok"`, while a failed optional dependency produces a
warning. The installer and updater accept that documented HTTP-200 state and name
the affected dependencies. HTTP failures, failed or missing required database
checks, inconsistent status values and malformed JSON still fail without moving
the installed-version record. Startup retries stay quiet; a final failure keeps
the response in the printed release directory and points to the service journal.

This backup covers the installer's default local paths. If you move storage or
use an external database, arrange matching backups separately. A failed update
can leave services stopped. Inspect its error and backup before retrying. Do not
start an older package against a migrated database: restore a matching backup
or the whole Proxmox container instead. Do not blindly rerun the installer.

## Check the result

Inside the new container:

```bash
systemctl is-active initiative-server nginx postgresql
curl --fail http://127.0.0.1:8173/api/v1/readyz
curl --insecure --fail https://127.0.0.1/api/v1/readyz
```

Expected: all three services are active and both readiness responses report
`"status":"ok"`, or `"status":"degraded"` with all three database checks `"ok"`.
Investigate the dependencies named `"error"` in a degraded response; they are
warnings rather than a failed installation. `--insecure` is only used here to
probe the local self-signed HTTPS endpoint.

For a failed start:

```bash
systemctl status initiative-server nginx postgresql --no-pager
journalctl -u initiative-server -n 100 --no-pager
```

Do not paste `server.env`, database passwords or account credentials into an
issue or chat.

### Recover an upgrade rejected by the old readiness check

The old script required every check to be `"ok"`, so it could report failure
after the package upgrade succeeded. For the reported 0.76.0 to 0.77.1 update,
the saved response supplied by the operator confirmed `"status":"degraded"`
with only `notify_bus` reporting `"error"`. All three database checks, storage
and the rate-limit store were `"ok"`. This is the exact response already covered
by the degraded-readiness regression fixture. A subsequent independent HTTPS
check confirmed v0.77.1 with every readiness check, including `notify_bus`, `"ok"`.

If the app is running normally, these commands **inside the container** reload
the package unit and reconcile the version marker without reinstalling,
restarting the server or creating another backup:

```bash
(
  set -o pipefail
  systemctl daemon-reload &&
    curl --fail --silent --show-error http://127.0.0.1:8173/api/v1/readyz |
    jq -e '.status == "ok" and .checks.database == "ok" and .checks.database_system == "ok" and .checks.database_provisioning == "ok"' >/dev/null &&
    cat /usr/lib/initiative/VERSION > /root/.initiative
)
```

The marker is changed only after a fully healthy response; if that check fails,
inspect readiness and the journal before doing anything else. Keep the existing
pre-update backup until you have checked your data. The updated fork script is
used by subsequent `update` runs automatically.

The operator has already reported a real amd64 Proxmox installation and a
0.76.0 to 0.77.1 package upgrade. Complete these remaining acceptance checks
with the corrected updater:

1. Retest creation of an unprivileged Debian 13 container through the wizard
   with the current branch.
2. Open HTTPS from your browser and create the first owner account.
3. Create a community, initiative, project and task; upload a file and exercise
   live document editing. Confirm a second public registration is rejected.
4. Reboot the container and confirm the app, task and upload remain available.
5. Run `update`. A current installation should leave services and data alone.
   When another server release is available, verify the upgrade and backup,
   then recheck your task, upload and login.

## Validation and handoff

Local validation commands, from the fork checkout:

```bash
bash -n ct/initiative.sh install/initiative-install.sh .github/workflows/scripts/initiative-test.sh
shellcheck -e SC1090,SC1091,SC2154 ct/initiative.sh install/initiative-install.sh .github/workflows/scripts/initiative-test.sh
bash .github/workflows/scripts/initiative-test.sh
jq -e . json/initiative.json
git diff --check
```

The ShellCheck exclusions cover dynamic framework imports and variables supplied
by Community Scripts. All 35 regression scenarios passed. The harness runs
without root or network access; it verifies checksum rejection, server-versus-
desktop package selection, the architecture and OS guards, missing assets,
unavailable or inconsistent readiness, valid degraded responses with named
warnings, failed backups, a still-running database, unit reload before start,
current-version no-op behavior, successful install/update ordering and the
documented recovery command's failure gates. The Bash Syntax Check workflow
runs this harness on pull requests and pushes to `main`.

A disposable **Debian 13 arm64 VM** also passed these checks using Initiative
v0.76.0 and the real shared core helpers:

- Release asset download and SHA-256 verification, native package installation,
  PostgreSQL bootstrap, nginx HTTPS and systemd service activation as `initiative`.
- First-owner registration with public registration disabled, login, rejection of
  subsequent public registration, community/initiative/project/task creation,
  SPA delivery and the signed native update manifest.
- Reapplying the same release through the updater after setting an older version
  marker: offline database-cluster backup, correct backup permissions, restart,
  unchanged configuration and upload checksums, and preserved login/task data.
- A second update on the current version performed no service restart.

The guest harness supplied the framework's environment and replaced the host
wizard, container provisioning, OS-update, resource-check and MOTD/cleanup steps.
Application installation and updater commands used real services and packages.
The cached-release skip found by this test was corrected by forcing downloads
into each fresh staging directory. The database shutdown check also required
stopping Debian's `postgresql@17-main` cluster unit explicitly.

Native validation used core commit
`1ed248530539400a584892d9930b97cd9b823b92`, against DevScripts base
`2484a382cafe659ff63ffcf656a4e75f79975c02`. Development logs are local evidence,
not hosted CI artifacts. These guest checks do not establish arm64 LXC support
or verify the Proxmox wizard. Separately, the operator's amd64 Proxmox run
installed v0.76.0 and upgraded the official package to v0.77.1; subsequent HTTPS
checks confirmed that version and healthy readiness. The corrected full updater
has not been rerun on that container. Browser interactions, reboot persistence,
and preservation of real user data across the upgrade remain unverified.

## PR #2484 CI repair handoff

The `ct scripts base` workflow checks every CT script, including existing ones.
Its failure on the initial Initiative submission came from `ct/jumpserver.sh`,
the only script missing `_CS_DEFAULT_URL`. The repair sets that value before
loading the engine, so a remotely fetched Jumpserver script selects DevScripts'
installer instead of falling back to ProxmoxVE. Initiative already declares the
correct default. An explicit `COMMUNITY_SCRIPTS_URL` still selects a fork or
branch for either script; keep it exported when testing this PR.

The repair preserves the native installer, updater, checksum verification,
database backups and all 35 offline regression cases. Applicable local checks
are the commands above, Bash syntax and ShellCheck for `ct/jumpserver.sh`,
`actionlint .github/workflows/ct-base.yml .github/workflows/bash-syntax.yml`,
and the complete scripts-base and syntax loops from those workflows. Local
source-resolution checks exercise the shared engine's default and explicit URL
selection without running an installer. These checks establish source routing
and shell behavior, not a container deployment.

Jumpserver's existing updater has seven ShellCheck `SC2164` warnings about
unguarded directory changes. The repair adds no diagnostics; these pre-existing
warnings remain outside this scripts-base repair. Initiative's scripts and
regression harness pass ShellCheck with the framework exclusions above.

The separate PR requirements failure is still the unmet **600+ GitHub stars**
requirement. The upstream repository currently has 192 stars, was created on
2025-11-22, remains active and publishes official releases and native packages.
Keep the star checkbox unchecked and the PR in draft. Maintainers must decide
the adoption exception; do not relabel the contribution or bypass the check.
Fresh corrected-branch Proxmox testing, browser/file/live-editor behavior, reboot
persistence and the corrected full updater's preservation of real user data
remain operator acceptance work in issue #2483. No deployment is part of this
CI repair.

## Sources

- [Initiative v0.76.0 release and server assets](https://github.com/beyonders-studio/initiative/releases/tag/v0.76.0)
- [Native package instructions](https://github.com/beyonders-studio/initiative/blob/v0.76.0/docs/en/running-a-server/native-packages.md)
- [Package lifecycle and service](https://github.com/beyonders-studio/initiative/tree/v0.76.0/packaging/server)
- [Database bootstrap implementation](https://github.com/beyonders-studio/initiative/blob/v0.76.0/backend/app/db/bootstrap.py)
- [First-owner registration behavior](https://github.com/beyonders-studio/initiative/blob/v0.76.0/backend/app/api/v1/platform_endpoints/auth.py)
- [DevScripts contribution and AI instructions](https://github.com/community-scripts/DevScripts/blob/main/AGENTS.md)
- [Fork and branch source selection](https://github.com/community-scripts/DevScripts/blob/main/docs/guides/source-origin.md)
- [Shared core engine](https://github.com/community-scripts/core)
