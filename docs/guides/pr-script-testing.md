# Testing PR Scripts on Proxmox and Incus

Every push to a pull request (drafts excepted) makes self-hosted runners build
every `ct/` and `vm/` script the PR touches: each `ct/` script on a real Proxmox
VE host **and** on an Incus host, each `vm/` script on Proxmox. On top of that,
each `ct/` script is built on ARM64, as information only. The result comes back
as a **Proxmox script test** check run and as a single PR comment that is kept
up to date.

The workflow is [`pr-script-test.yml`](../../.github/workflows/pr-script-test.yml).
The same file runs in DevScripts and ProxmoxVE.

## Using it

**Automatic on every PR, forks included:** each push to a PR that changes a
`ct/`, `install/` or `vm/` script is built without anyone asking. That means
contributors' code runs unattended on the lab hosts, a decision taken on
2026-11-12: the hosts are isolated, hold no secret and are treated as
compromised anyway. A draft is built once it is marked ready for review.

Each PR has one queue. A push while a test is running waits for it and then
builds the newest commit; pushes in between are skipped. A running test is
never cancelled, because a cancelled job leaves its container behind.

**Approved automatically: only scripts moving over from DevScripts
(ProxmoxVE).** PRs that the `push-app-to-main` app opens on a branch of the
repository itself are approved when every script passes. They were reviewed
and tested in DevScripts already, and only writers can push to such a branch.
In ProxmoxVE that approval counts as the one approval the `main` ruleset
requires, so a passing migration PR becomes mergeable; a new push dismisses it
as stale, and a later run that does not fully pass withdraws it. 🖥️ and ⚠️
results are never approved. Every other PR gets the report and the check, and
"changes requested" when a script really fails.

`/test` is for building again, or for picking scripts and platforms:

| Comment | Builds |
| ------- | ------ |
| `/test` | The latest commit: every `ct/` and `vm/` script the PR changes, plus the `ct/` entry point of every changed `install/` script |
| `/test ct/foo.sh vm/bar-vm.sh` or `/test foo bar-vm` | Only these scripts. An app name means its `ct/` script, or its `vm/` script if there is no `ct/` one |
| `/test arm` | Every platform word limits where it builds: `pve` (or `proxmox`), `incus`, `arm` (or `arm64`) |
| `/test arm pve foo bar` | Combined: `foo` and `bar`, on ARM64 and Proxmox only. The words can come in any order |
| `/test <sha>` | Exactly that commit (all 40 characters), and only while it is the PR head |
| `/test <app> [<app> ...]` **in an issue** | That app from the default branch as it is now, e.g. to check whether a reported error reproduces. Install and update test as for a PR; no check run, review or approval. Platform words work here too (`/test arm bark-server`) |
| The **Ready For Testing** label on a script issue | No comment needed: the app the issue names (its "Script path" field, else "Name of the Script" as a slug, like `Label Studio` → `label-studio`) is built from the default branch, as `/test <app>` in that issue would. Issues for `tools/` scripts are skipped |

A run on only some platforms is a partial test. It reports under its own
check (`Proxmox script test (pve only)`), so it never stands in for the full
one. Its pass never approves a PR and never lifts an earlier "changes
requested"; a failure still requests changes. `/test arm` alone counts for
nothing: its check is neutral. VM scripts are built on `pve` only, so a run
without `pve` lists them under "Not built".

- Only users with write access can comment `/test`. Anyone else's is ignored.
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
  a row per platform. Platform words in the `/test` narrow this down.
- Scripts that ask for the OS (`msg_menu "Choose the container OS"`) are built
  twice per platform, once on Debian and once on Alpine.
- Every `ct/` script is also built on **ARM64** (`arm64` in the comment), see
  below. That row is information only.
- At most 10 scripts per run (each can be up to six builds).
- `tools/` and `turnkey/` scripts are not built yet, and ARM64-only VM scripts
  (`vm_require_arch arm64`) never are: the test hosts are amd64. The comment
  lists them under "Not built".
- You can also start it from the Actions tab (`workflow_dispatch`) with a PR
  number; its `scripts` field takes the same app names, paths and platform
  words.

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
4. The URL the script prints (`http://${IP}:PORT/...`) answers within 2
   minutes, and not with an error: no answer, 404/410, any 5xx, or a redirect
   loop fail it; anything else passes, including 401/403 from a login wall.
   Redirects are followed, so a jump to a login page is fine. Scripts
   that print no URL skip this check.
5. **Update:** the installed app is set back (every version file the install
   wrote, `~/.<app>`, whose name the script passes to `check_for_*release`
   gets `-dev` appended, e.g. `6.7.16.0-dev`, which the engine ranks below the
   release while scripts that read the installed series still see `6.7`; a
   commit hash becomes `0.0.0-ci`; helpers the update never checks, like `~/.mise`, stay
   as they are), and `update` runs inside the
   container the way a user would run it, pulling the PR's `ct/` script. It has
   to finish without an error and report "Updated successfully"; then checks 3
   and 4 run again. An app without a version file (apt, npm, ...) only gets
   "nothing to update" (➖), which is not a failure. A GitHub API rate limit
   during the update is ⚠️ (not tested), not ❌; the job passes its read-only
   token to the build so that this should not happen. Apps deployed from a
   branch (`check_for_gh_branch`) store a commit hash instead of a version;
   it is set back the same way.
6. **Second update:** right after a real update, `update` runs again. It must
   finish without an error and leave the app working (checks 3 and 4). If it
   updates again although nothing changed, that is a note, not a failure.
7. **Stays up:** for 60 seconds nobody touches the container; no service (and
   no Docker container) may restart in that time, and checks 3 and 4 must
   still pass afterwards. That catches crash loops that look "active" at any
   single moment.

**Upgrade test (`pve · upgrade`, ProxmoxVE only).** When a PR changes
`update_script()` in a `ct/` script that already exists on the base branch,
the script is built once more on Proxmox: installed from the base branch as
it is now, then updated with the PR's script (checks 5 to 7), the way a user
who installed before the merge would update. With unchanged update code an
existing install updates exactly as it does today, so there is nothing new to
test; new scripts have nothing to upgrade from. DevScripts never runs it. If the install from the base branch fails, that row
is ⚠️ (not tested), not the PR's failure.

**Notes (information only, never counted):**

- **Resources:** disk used against the size, RAM in use at rest (without the
  page cache) against the limit, and OOM kills over the container's life, the
  build included. Shown in a collapsed "Resources" table; disk over 90 %, RAM
  at rest over 80 % of `var_ram`, or any OOM kill becomes a note that
  `var_disk`/`var_ram` may be too small.
- **Journal:** error lines in the container's journal since boot, with the
  two most frequent.
- A second update that updated again.

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
   (`http://${VM_IP}:9000`), that URL answers within 10 minutes, by the same rule as check 4. The
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

Three Proxmox hosts and two Incus hosts, all **single-use**: every job starts
on a host that was just reset, and the host is reset again afterwards. Each
host serves one repository: ProxmoxVE has two Proxmox hosts (so an upgrade
row does not hold up the normal one), DevScripts one; each has one Incus
host.

| Host | VM | Repository |
| ---- | -- | ---------- |
| `pve-ci` | 200 | DevScripts |
| `pve-ci-2` | 201 | ProxmoxVE |
| `pve-ci-3` | 204 | ProxmoxVE |
| `incus-ci` | 202 | DevScripts |
| `incus-ci-2` | 203 | ProxmoxVE |

### Single-use hosts

PR code runs as root on these hosts, forks included and without anyone
looking first. A long-lived host would let one PR plant something that fakes
the results of the next, or copy the runner's credentials and pose as a
runner elsewhere. So a controller on prox1, which never runs PR code, keeps
each host single-use
([`ci-vm-controller.sh`](../../.github/workflows/scripts/ci-vm-controller.sh),
one `ci-vm-controller@<vmid>` service per VM):

1. It rolls the VM back to its `clean` snapshot and boots it (about 1.5
   minutes).
2. It registers a just-in-time runner for the host's repository
   (`generate-jitconfig`). That runner takes exactly one job, and GitHub
   deletes it afterwards, so its credentials are worthless once the job is
   over. It has only the label `proxmox-test` or `incus-test`, never
   `self-hosted`.
3. When GitHub reports the runner gone, it starts over. When a job is over is
   read from GitHub, never from the VM, which may be compromised by then.

One repository per host, because a job could read the waiting runner of
another repository on the same host and use it elsewhere before it is
withdrawn.

The controller's GitHub token is in `/etc/ci-controller/token` on prox1: a
fine-grained token for DevScripts and ProxmoxVE with only Administration:
read and write. Per-VM settings are in `/etc/ci-controller/<vmid>.conf`;
[`ci-controller-setup.sh`](../../.github/workflows/scripts/ci-controller-setup.sh)
installs all of it. Logs: `journalctl -u ci-vm-controller@200`.

Stopping a controller leaves its VM as it is; starting it resets the VM, which
also ends a job that is still running there.

The VM disks are on the thin pool `SAN_PROX1_CI` (in `SAN_PROX1`, prox1
only), because shared LVM (`SAN_SHARED`) cannot take snapshots.

### Proxmox VE

| | |
| - | - |
| Hosts | VM 200 `pve-ci` (`10.201.146.232`), VM 201 `pve-ci-2` (`10.201.146.231`) and VM 204 `pve-ci-3` (`10.201.146.235`, 8 cores, 16 GB), all on prox1, Proxmox VE 9 |
| CPU | Xeon E5-2650 (Sandy Bridge): AVX, no AVX2. prox3 has the same CPU |
| Disk | 250 GB each (thin) on `SAN_PROX1_CI`. `local-lvm` on prox1 manages only ~4 fsyncs/s, which turns every `dpkg --configure` into minutes |
| Runners | Single-use, from `/opt/actions-runner/<repo>`, named `<host>-<repo>-<time>`, label `proxmox-test` |
| Containers | Bridge `vmbr1`, `10.99.0.0/24`, NAT to the lab network, DHCP and DNS from dnsmasq |
| Container IDs | DevScripts `9000–9049`, ProxmoxVE `9050–9099`, on each host (every host is its own Proxmox) |
| VM IDs | DevScripts `9100–9149`, ProxmoxVE `9150–9199`. Nested KVM: prox1 has `nested=Y` and the hosts' CPU type is `host` |
| Image cache | Container templates are in the snapshot. VM images and ISOs a job downloads are gone with the next reset |
| PR trees | `/srv/ci`, served on `10.99.0.1:18080` |
| Sweeper | `ci-sweep.timer` is still installed, but the reset after every job already removes whatever a job leaves behind |

### Incus

| | |
| - | - |
| Hosts | VM 202 `incus-ci` (`10.201.146.233`) and VM 203 `incus-ci-2` (`10.201.146.234`), both on prox1, Debian 13 with Incus 6.0 LTS |
| Size | 8 cores, 16 GB RAM, 150 GB (thin) on `SAN_PROX1_CI` each; storage pool `default` (dir) |
| Runners | Single-use, from `/opt/actions-runner/<repo>`, named `<host>-<repo>-<time>`, label `incus-test` |
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

Then install the runner software for the host's repository, without
registering anything:

```bash
bash pve-ci-host-setup.sh community-scripts/DevScripts jit
```

On prox1, shut the VM down, take the snapshot the controller resets to, and
start its controller (after adding the VM to `ci-controller-setup.sh` if it
is new). Every disk of the VM must be on storage that can take snapshots,
the EFI disk included:

```bash
qm shutdown <vmid> && qm snapshot <vmid> clean
```

```bash
systemctl enable --now ci-vm-controller@<vmid>
```

To update a host (packages, templates, runner version), stop its controller,
start the VM, change it, shut it down, and replace the snapshot
(`qm delsnapshot <vmid> clean`, then `qm snapshot <vmid> clean`). Never
snapshot a VM that has run a job since its last reset.

Give a new host a static address in cloud-init from its first boot: the lab
DHCP once gave a new host the address of an existing one.

## Security model

- `gate` and `report` run on GitHub-hosted runners. Only they hold write tokens.
- `test` runs on a self-hosted runner with a read-only token and no secrets.
  The harness comes from the default branch; only the script under test comes
  from the PR.
- Every job gets a freshly reset host and a runner that is valid for that one
  job (see [Single-use hosts](#single-use-hosts)). Nothing a PR does on a
  host survives into the next job, and no runner credential outlives it.
- Every value that reaches the host (repository, commit, path, OS, platform)
  is checked against a strict pattern before use.
