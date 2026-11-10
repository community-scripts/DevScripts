# Testing PR Scripts on Proxmox

A maintainer comments `/test` on a pull request, and a self-hosted runner builds
every `ct/` script the PR touches on a real Proxmox VE host. The result comes
back as a **Proxmox script test** check run and as a single PR comment that is
kept up to date.

The workflow is [`pr-script-test.yml`](../../.github/workflows/pr-script-test.yml).
The same file runs in DevScripts and ProxmoxVE.

## Using it

| Comment | Builds |
| ------- | ------ |
| `/test <sha>` | Every `ct/` script the PR changes, plus the `ct/` entry point of every changed `install/` script |
| `/test <sha> ct/foo.sh ct/bar.sh` | Only these scripts |

- Only users with write access can trigger it. Anyone else's `/test` is ignored.
- `<sha>` is the commit you reviewed, all 40 characters. A short SHA is refused:
  the PR author writes both commits, so making a malicious one share a short
  prefix with the reviewed one is a quick birthday collision. If the PR has been
  pushed to since, nothing is built, and the bot replies with the command for
  the current head. A plain `/test` gets the same reply, so you never have to
  look the SHA up yourself.
- Why it is required: without it, the job would build whatever the head is
  when it starts, and a contributor could push unreviewed code in the seconds
  between your comment and the build.
- Scripts that ask for the OS (`msg_menu "Choose the container OS"`) are built
  twice, once on Debian and once on Alpine.
- At most 10 scripts per run.
- You can also start it from the Actions tab (`workflow_dispatch`) with a PR
  number.

## What counts as passing

1. The script exits 0 within 45 minutes and prints `Completed successfully`.
2. The container is running.
3. No failed systemd units (Alpine: no crashed OpenRC services).
4. The URL the script prints (`http://${IP}:PORT/...`) answers with any HTTP
   status below 500 within 2 minutes. Scripts that print no URL skip this check.

The container is destroyed afterwards, whether the build passed or failed. The
full build log is attached to the run as a `result-*` artifact.

## How a fork branch gets built

The engine fetches everything from `raw.githubusercontent.com/<repo>/main`: the
`ct/` script, then `build.func`, the install script, `install.func` and
`tools.func`. So the test host downloads the PR at the approved commit, rewrites
every upstream `main` URL in it to point at its own HTTP server, and builds from
there. Engine changes in the PR are tested along with the script.

## The test host

| | |
| - | - |
| Host | VM 200 `pve-ci` on prox1, `10.201.146.117`, Proxmox VE 9 |
| Disk | 250 GB on `SAN_SHARED`. `local-lvm` on prox1 manages only ~4 fsyncs/s, which turns every `dpkg --configure` into minutes |
| Runners | `/opt/actions-runner/<repo>`, label `proxmox-test`, one per repository |
| Containers | Bridge `vmbr1`, `10.99.0.0/24`, NAT to the lab network, DHCP and DNS from dnsmasq |
| Container IDs | DevScripts `9000–9049`, ProxmoxVE `9050–9099` |
| PR trees | `/srv/ci`, served on `10.99.0.1:18080` |
| Sweeper | `ci-sweep.timer`, every 3 hours: removes containers no running job holds |

The host runs pull request code as root. Treat it as disposable: never put
secrets on it, and rebuild it rather than repair it.

### Rebuilding it

Start from a fresh Proxmox VE 9 install, then run:

```bash
bash pve-ci-host-setup.sh
```

To register a runner, get a registration token first. It is valid for one hour.

```bash
gh api -X POST repos/community-scripts/DevScripts/actions/runners/registration-token --jq .token
```

```bash
bash pve-ci-host-setup.sh community-scripts/DevScripts <token>
```

Run the second command once per repository.

## Security model

- `gate` and `report` run on GitHub-hosted runners. Only they hold write tokens.
- `test` runs on the self-hosted runner with a read-only token and no secrets.
  The harness comes from the default branch; only the script under test comes
  from the PR.
- Every value that reaches the host (repository, commit, path, OS) is checked
  against a strict pattern before use.
