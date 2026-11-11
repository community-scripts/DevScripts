# Testing PR Scripts on Proxmox and Incus

A maintainer comments `/test` on a pull request, and self-hosted runners build
every `ct/` and `vm/` script the PR touches: each `ct/` script on a real Proxmox
VE host **and** on an Incus host, each `vm/` script on Proxmox. On top of that,
each `ct/` script is built on ARM64, as information only. The result comes back
as a **Proxmox script test** check run and as a single PR comment that is kept
up to date.

The workflow is [`pr-script-test.yml`](../../.github/workflows/pr-script-test.yml).
The same file runs in DevScripts and ProxmoxVE.

## Using it

**Automatic for scripts moving over from DevScripts (ProxmoxVE):** PRs that the
`push-app-to-main` app opens on a branch of the repository itself are built on
every push without anyone asking, and approved when every script passes. They
were reviewed and tested in DevScripts already, and only writers can push to
such a branch. In ProxmoxVE that approval counts as the one approval the
`main` ruleset requires, so a passing migration PR becomes mergeable; a new
push dismisses it as stale, and a later run that does not fully pass
withdraws it. 🖥️ and ⚠️ results are never approved. All other PRs need `/test`.

| Comment | Builds |
| ------- | ------ |
| `/test` | The latest commit: every `ct/` and `vm/` script the PR changes, plus the `ct/` entry point of every changed `install/` script |
| `/test ct/foo.sh vm/bar-vm.sh` | Only these scripts |
| `/test <sha>` | Exactly that commit (all 40 characters), and only while it is the PR head |
| `/test <app> [<app> ...]` **in an issue** | That app from the default branch as it is now, e.g. to check whether a reported error reproduces. Install and update test as for a PR; no check run, review or approval. A name without a `ct/` script is looked up in `vm/` (`/test debian-vm`) |

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
- Every `ct/` script is built on both platforms, Proxmox VE (`pve`) and Incus
  (`incus`): the same files, which community-scripts/core runs through its
  Incus backend when it finds `incus` instead of `pveversion`. The comment has
  a row per platform.
- Scripts that ask for the OS (`msg_menu "Choose the container OS"`) are built
  twice per platform, once on Debian and once on Alpine.
- Every `ct/` script is also built on **ARM64** (`arm64` in the comment), see
  below. That row is information only.
- At most 10 scripts per run (each can be up to six builds).
- `tools/` and `turnkey/` scripts are not built yet, and ARM64-only VM scripts
  (`vm_require_arch arm64`) never are: the test hosts are amd64. The comment
  lists them under "Not built".
- You can also start it from the Actions tab (`workflow_dispatch`) with a PR
  number.

## ARM64 (information only)

Every `ct/` script is also built on GitHub's own arm64 runner
(`ubuntu-24.04-arm`): a fresh Ubuntu VM per job, on which
[`arm-runner-setup.sh`](../../.github/workflows/scripts/arm-runner-setup.sh)
sets up Incus (6.0 LTS from Zabbly, key pinned; Ubuntu's own 6.0.0 lacks the
`csv,noheader` output the engine uses) and the screenshot browser. The build
is the Incus one, unchanged, on native ARM: about as fast as on x86.

- **Never decides anything.** The ARM rows are shown in the table, but the
  headline, the check run, "changes requested" and the approval only count
  Proxmox and Incus. The ARM job runs with `continue-on-error`, so a failed
  ARM build, or one GitHub cannot run at all, never turns the run red.
- **`var_arm64`:** a script with `var_arm64="${var_arm64:-no}"` is not built
  on ARM (listed under "Not built"). `yes` is built as is. A script that leaves
  it unset (the engine would refuse to guess on ARM) is built with
  `var_arm64=yes`, to show whether setting it would work.
- **Cost:** standard GitHub-hosted runners, arm64 included, are free for
  public repositories. Jobs count against the organisation's concurrency
  limit, shared with every other workflow.
- **Without a PR:** the *ARM script test (manual)* workflow
  ([`arm-script-test.yml`](../../.github/workflows/arm-script-test.yml)) builds
  one script and branch on ARM from the Actions tab and posts nothing.

## What counts as passing

1. The script exits 0 within 45 minutes and prints `Completed successfully`.
2. The container is running.
3. No failed systemd units (Alpine: no crashed OpenRC services).
4. The URL the script prints (`http://${IP}:PORT/...`) answers **200** within 2
   minutes. Redirects are followed, so a jump to a login page is fine. Scripts
   that print no URL skip this check.
5. **Update:** the installed app is set back (every version file the install
   wrote, `~/.<app>`, whose name the script passes to `check_for_*release`
   becomes `0.0.0-ci`; helpers the update never checks, like `~/.mise`, stay
   as they are), and `update` runs inside the
   container the way a user would run it, pulling the PR's `ct/` script. It has
   to finish without an error and report "Updated successfully"; then checks 3
   and 4 run again. An app without a version file (apt, npm, ...) only gets
   "nothing to update" (➖), which is not a failure. A GitHub API rate limit
   during the update is ⚠️ (not tested), not ❌; the job passes its read-only
   token to the build so that this should not happen.

### VM scripts (`vm/`)

A VM script runs unattended (`VM_UNATTENDED=1`): its own defaults, with the
VM ID, name, bridge (`vmbr1`) and storage set by the test. The VM then boots
on the test network like the containers do. What passes:

1. The script exits 0 within 45 minutes and reports success: `Completed
   successfully`, or the closing ✔ line of `vm_finish` (newer scripts print
   their own text there). `exit_script` and friends also exit 0, but on a ✖.
2. The VM is running, and keeps running for the 5-minute boot wait. A VM that
   powers itself off or crashes fails.
3. Where the script prints a URL built from the address it found
   (`http://${VM_IP}:9000`), that URL answers **200** within 10 minutes. The
   address is the one the test network's DHCP gave the VM. A `<VM-IP>` hint
   in a summary is not checked: it usually means "after you ran the
   installer".

A VM that got no address (an installer ISO, an image without DHCP) is
reported as such, not failed. There is no update test, because a VM has no
`update` command. The screenshot is of the web UI when there is one, and
otherwise of the VM's console, taken straight from QEMU. Only one VM build
runs per host at a time; a second one waits.

The container or VM is destroyed afterwards, whether the build passed or failed. The
full build log is attached to the run as a `result-*` artifact.

**A broken app does not fail the workflow run.** The run says whether the
test worked, not whether the app did: a script that fails to build is a
result, reported on the PR as ❌ (failed check, comment, changes requested),
while the run on the Actions tab stays green so nobody gets a failure mail per
broken PR. A run only goes red when the test setup itself broke (no free
container ID, the PR could not be downloaded, the runner died); the PR then
shows ⚠️ with no changes requested, because it is not the author's fault.

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

## The test hosts

Two Proxmox hosts and two Incus hosts. Each has a runner for both
repositories, so GitHub hands every job to whichever host of its platform is
free: two builds per repository and platform can run at once.

### Proxmox VE

| | |
| - | - |
| Hosts | VM 200 `pve-ci` (`10.201.146.232`) and VM 201 `pve-ci-2` (`10.201.146.231`), both on prox1, Proxmox VE 9 |
| CPU | Xeon E5-2650 (Sandy Bridge): AVX, no AVX2. prox3 has the same CPU |
| Disk | 250 GB each on `SAN_SHARED`. `local-lvm` on prox1 manages only ~4 fsyncs/s, which turns every `dpkg --configure` into minutes |
| Runners | `/opt/actions-runner/<repo>`, named `<host>-<repo>`, label `proxmox-test`, one per repository per host |
| Containers | Bridge `vmbr1`, `10.99.0.0/24`, NAT to the lab network, DHCP and DNS from dnsmasq |
| Container IDs | DevScripts `9000–9049`, ProxmoxVE `9050–9099`, on each host (every host is its own Proxmox) |
| VM IDs | DevScripts `9100–9149`, ProxmoxVE `9150–9199`. Nested KVM: prox1 has `nested=Y` and the hosts' CPU type is `host` |
| Image cache | VM images and ISOs stay in `/var/lib/vz/template/{cache,iso}` between builds; the sweeper removes any unused for a week |
| PR trees | `/srv/ci`, served on `10.99.0.1:18080` |
| Sweeper | `ci-sweep.timer`, every 3 hours: removes containers and VMs no running job holds. A job holds its guest with a lock in `/run/ci-jobs`; a lock older than 3 hours (longer than any job runs) is a killed job's and is ignored and removed |

### Incus

| | |
| - | - |
| Hosts | VM 202 `incus-ci` (`10.201.146.233`) and VM 203 `incus-ci-2` (`10.201.146.234`), both on prox1, Debian 13 with Incus 6.0 LTS |
| Size | 8 cores, 16 GB RAM, 150 GB on `SAN_SHARED` each; storage pool `default` (dir) |
| Runners | `/opt/actions-runner/<repo>`, named `<host>-<repo>`, label `incus-test` |
| Containers | Bridge `incusbr0`, `10.98.0.0/24`, NAT; DHCP and DNS from Incus |
| Container names | `ci-9000`–`ci-9049` (DevScripts), `ci-9050`–`ci-9099` (ProxmoxVE), set through `var_ctid` |
| PR trees | `/srv/ci`, served on `10.98.0.1:18080` |
| Sweeper | `ci-sweep.timer`, as on Proxmox |

The hosts run pull request code as root. Treat them as disposable: never put
secrets on them, and rebuild them rather than repair them.

### Rebuilding one

Start from a fresh Proxmox VE 9 install (or, for Incus, a fresh Debian 13),
then run `pve-ci-host-setup.sh` (or `incus-ci-host-setup.sh`):

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

Run the second command once per repository. The Incus script takes the same
arguments.

Give a new host a static address in cloud-init from its first boot: the lab
DHCP once gave a new host the address of an existing one.

## Security model

- `gate` and `report` run on GitHub-hosted runners. Only they hold write tokens.
- `test` runs on a self-hosted runner with a read-only token and no secrets.
  The harness comes from the default branch; only the script under test comes
  from the PR.
- Every value that reaches the host (repository, commit, path, OS, platform)
  is checked against a strict pattern before use.
