# Oracle box (`oc`)

Operations handbook for the Always Free ARM instance. Read this first when
picking the box up again after a break.

## The machine

| | |
|---|---|
| Shape | `VM.Standard.A1.Flex`, 2 OCPU / 12 GB, arm64 |
| Region | `ap-singapore-1`, AD `ygaM:AP-SINGAPORE-1-AD-1` |
| OS | Ubuntu 24.04 LTS (`noble`), Server image — headless by default |
| Public IP | `134.185.87.62` |
| Private IP | `10.0.0.229` |
| Boot volume | 193 GB, ~48 GB used |
| Login | `ubuntu`, SSH key only for shell; the account also has a password now, for RDP |

```bash
ssh oc                                          # alias in ~/.ssh/config
ssh -i ~/.ssh/oracle.key ubuntu@134.185.87.62   # the long form
```

Only port 22 is open from the internet. `iptables` ends in
`REJECT --reject-with icmp-host-prohibited`, and the OCI security list agrees.
Everything else reaches the box through the Cloudflare tunnel.

## Staying inside Always Free

Always Free A1 capacity is metered as **1,500 OCPU-hours and 9,000 GB-hours per
month** across all A1 instances, not as a fixed shape. One 2 OCPU / 12 GB
instance running continuously uses roughly 1,460 OCPU-hours and 8,760 GB-hours,
so a single box fits with very little room for a second one.

Other limits that apply: 200 GB of block storage in total, 5 volume backups,
10 TB of egress per month.

**Idle reclamation.** Oracle reclaims an Always Free compute instance only when
*all three* of these are true over the previous 7 days, at the 95th percentile:
CPU below 20%, network below 20%, and memory below 20%. Any one metric above
20% keeps the instance. Memory utilisation is
`(MemTotal - MemAvailable) / MemTotal`, not `used/total`:

```bash
awk '/MemTotal/{t=$2} /MemAvailable/{a=$2} END{printf "%.1f%%\n", (t-a)/t*100}' /proc/meminfo
```

This box idles at load ~0.01, so CPU and network are both far below 20% and
memory is the only metric holding the instance. Firecrawl is the main consumer
and puts it around 53%. Without Firecrawl it sits near 23%, which is above the
line but with only a few points of margin.

If more ballast is ever needed without running a real service, a tmpfs works and
costs no CPU, because tmpfs pages count as shared memory and lower
`MemAvailable`:

```bash
sudo mount -t tmpfs -o size=3G tmpfs /mnt/ballast
sudo dd if=/dev/zero of=/mnt/ballast/fill bs=1M count=2800
```

Switching to Pay As You Go keeps the Always Free resources but silently bills
anything above them, so check the shape before creating a second instance.

## What runs where

| Service | Port | Bind | Tunnel hostname | Supervised by |
|---|---|---|---|---|
| portainer | 9000, 9443 | `127.0.0.1` | `oc-portainer` | `docker compose` |
| termix | 5674 | `127.0.0.1` | `oc-termix` | `docker compose` |
| hindsight API | 8890 | `0.0.0.0` | — | `docker compose` |
| hindsight UI | 9991 | `0.0.0.0` | `oc-hindsight` | `docker compose` |
| 9router | 20128 | `0.0.0.0` | `oc-9router` | `docker compose` |
| searxng | 8888 | `0.0.0.0` | — | `docker compose` |
| beszel | 8090 | `127.0.0.1` | `oc-cp` | `docker compose` |
| firecrawl api | 3092 | `0.0.0.0` | — | `docker compose` |
| hermes-webui | 8787 | `127.0.0.1` | `oc-hermes` | systemd user unit |
| xrdp | 3389 | `127.0.0.1` | `oc-rdp` (`tcp://`) | systemd |

Every tunnel hostname is prefixed `oc-` so the box cannot collide with the
homelab inside the same `3p.id.vn` zone. The tunnel is named `oracle-sg` and is
configured locally in `/etc/cloudflared/config.yml`.

**The tunnel is not authentication.** Anything published through it needs its
own gate: the application's own login, or a Cloudflare Access policy.

This box does **not** run PM2. `pnpm start`, `services.json` and
`scripts/start.js` belong to the homelab; here every service already ships a
supervisor of its own. The systemd user unit needs lingering to survive a
reboot:

```bash
sudo loginctl enable-linger ubuntu
systemctl --user enable --now hermes-webui.service
```

## Helper scripts

Both need `sudo` and live in `/usr/local/bin`.

```bash
sudo tunnel add <sub> <port> [http|https|tcp]   # third argument defaults to http
sudo tunnel list
sudo tunnel remove <hostname>
sudo tunnel restart
```

`tunnel add` writes the ingress rule, creates the CNAME to
`<uuid>.cfargotunnel.com`, validates the config and restarts `cloudflared`. It
restores the previous config if validation fails. RDP and anything else that is
not HTTP needs the `tcp` scheme.

```bash
project add <path>    # register a directory in hermes' projects.db
project list
project which
project remove <path>
```

`project` lives in `stack/scripts/project` and is symlinked into
`/usr/local/bin`. It re-executes itself under
`~/.hermes/hermes-agent/venv/bin/python`, because the distribution's SQLite 3.45
prints a WAL reset warning against a database written by 3.53.

## Hermes and Hindsight

Hermes runs from `~/.hermes`, the CLI is at `~/.local/bin/hermes`. It is not on
the PATH of a non-interactive SSH command, so scripts need the full path.

`~/.hermes/hermes-agent` sits on branch **`hindsight-per-project`**, a
cherry-pick of upstream PR #97620 onto the release commit. That patch is what
makes the memory bank follow the workspace. Keep
`updates.parked_branch_strategy: update_in_place` in `config.yaml`: without it
`hermes update` switches back to `main` and silently disables the patch.

Bank resolution, in order:

1. `HINDSIGHT_BANK_ID` in the environment (CLI override)
2. `.hindsight/config.toml` in the current directory or a parent
3. `bank_id_template` in `~/.hindsight/config.json`
4. the hardcoded default

`~/.hindsight/config.json` holds:

```json
{"mode": "local_external", "bank_id_template": "bank-{workspace}", "bank_id": "hermes"}
```

Two things that do **not** work, and cost a lot of time to rediscover: the
`memory.hindsight` block in `~/.hermes/config.yaml` is display-only — the
provider's `_load_config()` never reads `config.yaml` — and AGENTS.md cannot
move the bank either, because the bank is resolved before the agent reads any
instructions.

The workspace convention is a wrapper directory holding docs and context with
several repositories cloned inside it, so one bank covers a whole product:

```
~/workspace/bmt-mgmt-wrapper/     -> bank-bmt-mgmt-wrapper
  .hindsight/config.toml
  bmt-fe/  bmt-be/  bmt-admin-fe/  bmt-admin-be/
```

Committing `.hindsight/config.toml` makes the bank travel with the repository,
but only to machines that also carry the cherry-pick. On stock Hermes the file
is ignored silently.

The WebUI works the same way: it sets `TERMINAL_CWD` per session, and
`resolve_agent_cwd()` reads `_SESSION_CWD` → `TERMINAL_CWD` → `os.getcwd()`.

## Claude Code

Installed with the native installer, so it carries its own runtime and does not
depend on the Node that Hermes bundles:

```bash
curl -fsSL https://claude.ai/install.sh -o /tmp/claude-install.sh   # read it first
bash /tmp/claude-install.sh                                         # never as root
```

The binary lands in `~/.local/bin/claude`. Ubuntu's stock `.profile` already
puts `~/.local/bin` on the PATH of a login shell, and `.bashrc` line 124 does
the same for an interactive one. Neither runs for a plain
`ssh oc 'claude ...'`, so scripts need the full path.

There is no self-hosted web interface. `claude.ai/code` runs its sessions in
Anthropic's own cloud, not on this box. To drive Claude Code here through a
browser, use the terminal that is already published: Termix at
`oc-termix.3p.id.vn`, or the desktop session over RDP. The desktop also has
VS Code, so the Claude Code extension works there.

First run prints an OAuth URL. From the desktop session Firefox opens it
directly; from Termix, copy the URL into a local browser and paste the code
back.

## Desktop

XFCE over RDP on the host itself, so it can be used as an ordinary workstation.
Full details in [desktop/README.md](desktop/README.md). The short version:

```powershell
cloudflared access rdp --hostname oc-rdp.3p.id.vn --url localhost:3389
mstsc     # localhost:3389, session Xorg, user ubuntu
```

## Common operations

```bash
# What is running, and what it costs
docker ps --format '{{.Names}}\t{{.Status}}'
docker stats --no-stream --format '{{.Name}}\t{{.MemUsage}}\t{{.CPUPerc}}'
free -m; df -h /

# Restart one service
cd ~/stack/<service> && docker compose up -d

# Update the git-backed services
~/stack/scripts/stack-update.sh          # logs to ~/stack/logs/stack-update.log

# Tunnel
sudo tunnel list
sudo systemctl status cloudflared
```

## Conventions and traps

- Every tunnel hostname starts with `oc-`.
- Services listen on `127.0.0.1` unless another container genuinely needs them.
  Portainer especially: it holds the docker socket, which is host root.
- `~/.bashrc` returns early for non-interactive shells. Anything appended below
  that line never runs — this has already broken nvm once and a hermes wrapper
  once. Put additions above the early return.
- `rsync` and `scp` carry git's `skip-worktree` bit inside `.git/`, which can
  hide a modified file on the destination. Clear the bit before trusting
  `git status` on a copied repository.
- Docker refuses to create a container when `cpus:` exceeds the host CPU count
  rather than clamping it. Upstream compose files that ask for 4 CPUs need an
  override here.
- `ports` lists **append** across compose files, they do not replace. Put host
  bindings in one file only.

## Repository layout

`~/stack` is `git@github.com:nmphat/stack.git`, branch `vps-reuse`. Submodules:
`hermes-webui` (upstream nesquena/master), `firecrawl` (fork
nmphat/stack-customizations), `harness-cloak` (fork nmphat/cloak).

Each service directory carries its own `README.md` and `.env.example`. Fork
customisations are documented in the fork's `STACK.md`, not its `README.md`, so
that rebases onto upstream stay clean.
