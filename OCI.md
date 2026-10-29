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
| 9router | 20128 | `0.0.0.0` | `oc-9router` | `docker compose` |
| searxng | 8888 | `0.0.0.0` | — | `docker compose` |
| beszel | 8090 | `127.0.0.1` | `oc-cp` | `docker compose` |
| firecrawl api | 3092 | `0.0.0.0` | — | `docker compose` |
| dsh | 3080 | `127.0.0.1` | `oc-dsh` | systemd user unit |
| n8n | 5678 | `127.0.0.1` | `oc-n8n` | `docker compose` |
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
systemctl --user enable --now dsh-web.service
```

## Helper scripts

The tunnel helper needs `sudo` and lives in `/usr/local/bin`.

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

## DeepSeek Harness (dsh)

The web UI on `oc-dsh.3p.id.vn`. Installed from npm into `~/stack/dsh`, so it
carries its own `node_modules` and does not share the system Node:

```bash
cd ~/stack/dsh
npm install                      # installs the pinned version
npm update @deepseek-ai/dsh      # bump within the pinned range
systemctl --user restart dsh-web
```

| | |
|---|---|
| Port | `3080` (loopback) |
| Tunnel | `oc-dsh` |
| Supervisor | systemd user unit `dsh-web.service` |
| Home | `~/.dsh` (profiles, sessions, settings) |

The unit at `~/.config/systemd/user/dsh-web.service` pins `PATH` to nvm's Node
and `DSH_HOME` to `~/.dsh`, and reads `~/stack/dsh/.env` for
`OC_9ROUTER_API_KEY`. That key belongs to the stack's own 9router gateway
(`http://localhost:20128/v1`), which is the route the Web UI and the headless
profile both use — not the DeepSeek SaaS endpoint. The startup log prints the
entry URL including the launch token; that token is a process credential, so
keep it private.

`dsh headless "<prompt>"` runs one task and prints the result, which is what
`scripts/stack-update.sh` uses for conflict resolution. The headless profile
carries the same provider patch as the web profile
(`~/.dsh/profiles/headless/cordis.patch.yml`); without it the call dies with
`MISSING_CREDENTIAL` on the `deepseek-official` route.

## Coding agents

### Claude Code

Installed with the native installer, so it carries its own runtime and does not
depend on any Node the stack installs:

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

### Command Code

A separate paid product (`commandcode.ai`), installed from npm:

```bash
npm i -g command-code
```

It needs Node 22 or newer; this box has v24 from nvm at
`~/.nvm/versions/node/v24.20.0`. The global prefix is that nvm directory, so
switching Node versions
with nvm leaves the package behind — reinstall it after any `nvm install`.

The package installs four names for the same entry point: `cmd`, `cmdc`,
`command-code` and `commandcode`. `cmd` is a very generic name; nothing else on
this box claims it today.

```bash
command-code status    # authentication state
command-code login     # opens a browser URL
```

Because nvm puts its bin directory on the PATH from `.bashrc`, these resolve in
an interactive or login shell but not in a plain `ssh oc 'command-code ...'`.

`/import claude` inside a session copies skills, agents, commands, MCP servers
and memory across from the Claude Code setup rather than configuring it twice.

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
  that line never runs — this has already broken nvm once and a CLI wrapper
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
`firecrawl` (fork nmphat/stack-customizations), `harness-cloak` (fork
nmphat/cloak).

Each service directory carries its own `README.md` and `.env.example`. Fork
customisations are documented in the fork's `STACK.md`, not its `README.md`, so
that rebases onto upstream stay clean.
