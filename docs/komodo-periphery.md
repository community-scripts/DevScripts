# Komodo Periphery addon

Install the native Komodo Periphery agent on an existing Debian or Ubuntu Docker
LXC or VM. It runs under systemd and connects outbound to an existing Komodo Core
v2 server. No Komodo Core or database is installed, no Docker TCP socket is exposed,
and Periphery's inbound server is disabled.

For a new Docker host, create a Docker LXC with the existing ProxmoxVE Docker
script, then run this addon **inside that LXC**. Periphery manages that host's
Docker containers and Compose stacks; it does not manage Proxmox LXC/VM resources.
Internet access is required for the shared engine and official Komodo releases.

## Install

Create a Server Onboarding Key in Komodo Core and run inside the Docker guest:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/community-scripts/DevScripts/main/tools/addon/komodo-periphery.sh)"
```

Enter the Core URL, a unique server name and the onboarding key. Secret input is
masked. Confirm the server's connection status in Komodo Core after installation:
an active systemd service alone does not confirm successful registration.

For a fork or branch, set the script source explicitly so the generated update
command continues to use it:

```bash
export COMMUNITY_SCRIPTS_URL=https://raw.githubusercontent.com/YOUR_USER/DevScripts/YOUR_BRANCH
bash -c "$(curl -fsSL "$COMMUNITY_SCRIPTS_URL/tools/addon/komodo-periphery.sh")"
```

The same script can be run from a local checkout. Set `COMMUNITY_SCRIPTS_CORE_DIR`
to a local `community-scripts/core` checkout to load the shared helpers locally.
The generated updater downloads its script from `COMMUNITY_SCRIPTS_URL`.

## Configuration

| Variable | Meaning | Default |
| --- | --- | --- |
| `var_komodo_core_address` | Reachable Core URL, such as `https://komodo.example.com` or `http://192.168.1.10:9120` | Prompted |
| `var_komodo_server_name` | Server name to register in Core | Guest hostname |
| `var_komodo_onboarding_key` | Server Onboarding Key | Required; prompted interactively |
| `var_komodo_core_public_key` | Optional trusted Core public key | Pin the first Core to `file:/etc/komodo/keys/core.pub` |
| `var_komodo_agent_version` | `latest` or a stable v2 release, with or without `v` | `latest` |

Supply variables before launching to avoid interaction. HTTPS requires a
certificate trusted by the guest. Core public keys and onboarding keys are
different credentials. The optional public key field allows explicitly pinning
a known Core instead of trusting the first connection.

Configuration is stored in `/etc/komodo/periphery.config.json` with mode `0600`.
Keys and stack/repository data live in `/etc/komodo`. After successful registration,
the onboarding key can be removed from the configuration and revoked in Core.
Preserve `/etc/komodo/keys` for subsequent authenticated connections.

The binary is `/opt/komodo-periphery/periphery`. Upstream publishes x86_64 and
aarch64 Linux binaries. ARM64 execution has not been verified by the contributor.
Alpine is not supported by this systemd addon.

## Updates

```bash
update_komodo_periphery
```

The selected version policy is persisted. To switch to an explicit release,
replace `v2.X.Y` below with a published version compatible with your Core:

```bash
var_komodo_agent_version=v2.X.Y update_komodo_periphery
```

To resume tracking the latest stable v2 release:

```bash
var_komodo_agent_version=latest update_komodo_periphery
```

The addon uses the shared release-check and download helpers. Downloads complete
before the agent is stopped. The previous binary and release cache are backed up
under `/opt/komodo-periphery.backup` and restored if the new agent cannot start.
Configuration, private keys, stacks and repositories are retained.

The addon updates Periphery only. Use the Docker LXC's existing `update` command
for Docker/system maintenance and Komodo for application container updates. The
addon does not replace an existing guest's `update` command. On a guest dedicated
to Periphery, you can explicitly choose the shorter command:

```bash
ln -sf /usr/local/bin/update_komodo_periphery /usr/local/bin/update
```

Verify `command -v update` resolves to this link before using it. Calling this
alias updates Periphery; it does not update Docker or application containers.

## Checks and existing installations

```bash
systemctl status periphery --no-pager
journalctl -u periphery -n 100 --no-pager
docker info
docker compose version
```

If Periphery was installed by another method, the addon refuses to overwrite its
configuration or service. An installation with the same binary/config paths as
this addon can use its update path without replacing configuration. Review those
paths before adopting an existing installation.

Sources: [Komodo setup](https://komo.do/docs/setup/connect-servers),
[upstream systemd installer](https://github.com/moghtech/komodo/blob/main/scripts/setup-periphery.py),
[Periphery configuration](https://github.com/moghtech/komodo/blob/main/config/periphery.config.toml).
