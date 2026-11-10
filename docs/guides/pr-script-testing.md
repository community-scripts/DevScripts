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
| `/test` | The latest commit: every `ct/` script the PR changes, plus the `ct/` entry point of every changed `install/` script |
| `/test ct/foo.sh ct/bar.sh` | Only these scripts |
| `/test <sha>` | Exactly that commit (all 40 characters), and only while it is the PR head |

- Only users with write access can trigger it. Anyone else's `/test` is ignored.
- Only a commit that existed when you wrote the comment is built. Otherwise a
  contributor could push unreviewed code in the seconds between your comment
  and the build. For a PR from a fork, the gate checks when that fork was last
  pushed to (`pushed_at`, set by GitHub); if that is after your comment,
  nothing is built and the bot asks you to comment again. Branches in this
  repository belong to people with write access and always build the latest
  commit.
- A pinned SHA has to be all 40 characters. The PR author writes both commits,
  so giving a malicious one the same short prefix is a quick birthday
  collision.
- Scripts that ask for the OS (`msg_menu "Choose the container OS"`) are built
  twice, once on Debian and once on Alpine.
- At most 10 scripts per run.
- You can also start it from the Actions tab (`workflow_dispatch`) with a PR
  number.

## What counts as passing

1. The script exits 0 within 45 minutes and prints `Completed successfully`.
2. The container is running.
3. No failed systemd units (Alpine: no crashed OpenRC services).
4. The URL the script prints (`http://${IP}:PORT/...`) answers **200** within 2
   minutes. Redirects are followed, so a jump to a login page is fine. Scripts
   that print no URL skip this check.

The container is destroyed afterwards, whether the build passed or failed. The
full build log is attached to the run as a `result-*` artifact.

A failed install counts as failed even though the engine, running with
`dev_mode=keep` so the install log can be read, still prints "Completed
successfully" afterwards.

**🖥️ Needs a newer CPU:** the test host is a Xeon E5-2650 (Sandy Bridge): AVX,
but no AVX2. A build or install that fails with an engine error such as
"requires AVX2" (also AVX-512, SSE4.2, x86-64-v2/v3/v4) is shown as 🖥️
instead of ❌, and the check asks for action (*action required*) instead of
failing: test it on newer hardware by hand. The log comes from the code under
test, so the claim only counts if the harness confirms in `/proc/cpuinfo`
that the host really lacks that feature; it never makes the check pass.

## What you see

- **Live output:** the `test` job's log on GitHub streams the build as it
  happens, including the install log from inside the container (lines marked
  `│`), which the engine normally hides. The PR comment links to it while the
  build runs. Workflow commands are switched off while that output streams,
  so a script cannot inject `::error` or similar into the log.
- **Result comment:** posted as a new comment that mentions whoever started the
  test and the PR's author, replacing the bot's previous one. An edited
  comment would not reliably notify. Text from the build that lands outside
  code blocks has its `@` defused, so a log line cannot ping anyone.
- **Review state:** a real failure (❌) requests changes on the tested commit,
  listing what failed. The next run dismisses that review: a pass lifts it,
  a new failure replaces it. 🖥️ (CPU), ⚠️ (runner trouble) and cancelled runs
  leave the review state alone; they are not the PR's fault.
- **Screenshot:** where the script prints a URL, headless Chromium (as the
  unprivileged user `ci-shot` on the test host) takes a 1280×800 screenshot, on
  a failed check too. It is stored on the orphan branch `ci-screenshots` as
  `pr-<n>/<script>.png`, overwritten on every run, and shown in the comment.
  Never merge that branch.
- **Install log:** collapsed in the comment for every script, the end of the
  build log as well for failures.

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
