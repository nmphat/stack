# Stack

Homelab service orchestrator. PM2 manages all services via `pnpm start`.

## Services

| Service | Type | Port | Source | Git | Update |
|---------|------|------|--------|-----|--------|
| 9router | CLI | 20128 | `scripts/9router.sh` | — | manual |
| portainer | Docker | 9000 | `portainer/` | — | `docker compose pull` |
| searxng | Docker | 8888 | `searxng/` | — | `docker compose pull` |
| termix | Docker | 5674 | `termix/` | — | `docker compose pull` |
| dsh | Git+systemd | 3080 | `dsh/` | npm `@deepseek-ai/dsh` | `npm update` |
| firecrawl | Git+Docker | 3092 | `firecrawl/` | submodule nmphat/stack-customizations | `stack-update.sh` |
| **cloak-browser** | **PM2** | **9222** | **`scripts/start-cloak-browser.sh`** | — | **auto via stack-update.sh** |

## Oracle VPS (`oc-` hosts)

Full operations handbook for that box: [OCI.md](OCI.md). It covers access,
the Always Free limits and the reclamation rule, every service and its port,
the dsh setup and the traps worth remembering.

The Oracle box does not run PM2. Every service there already ships a supervisor
of its own, so a third one would only add a layer that can disagree with them:

| Service | Supervised by |
|---|---|
| 9router, portainer, searxng, termix | `docker compose` with `restart: unless-stopped` |
| dsh | systemd user unit `dsh-web.service` |
| desktop (XFCE over RDP) | `xrdp` systemd unit, installed on the host |

`pnpm start`, `services.json` and `scripts/start.js` are the homelab's mechanism
and are unused on that host.

The systemd unit runs as the `ubuntu` user, so boot start needs lingering:

```bash
sudo loginctl enable-linger ubuntu
systemctl --user enable --now dsh-web.service
```

Nothing is published by binding to a public interface. Services listen on
loopback or on a published container port, and `cloudflared` is the only thing
that reaches the internet. Every hostname is prefixed `oc-`, which keeps the
VPS from colliding with the homelab in the same `3p.id.vn` zone:

```bash
sudo tunnel add oc-<name> <port>
tunnel list
```

The third argument picks the scheme. RDP is not HTTP, so it needs `tcp`:

```bash
sudo tunnel add oc-rdp 3389 tcp
```

Anything reachable through the tunnel needs its own auth — the tunnel is not one.

## Quick Start

```bash
git clone --recurse-submodules git@github.com:nmphat/stack.git
cd stack
./setup.sh
pnpm start
```


---

## Stack Manager Usage

The stack is managed via PM2 + pnpm. All services defined in `services.json`.

### Start All Services

```bash
pnpm start
```

### Stop All Services

```bash
pnpm stop
```

### Service Management

```bash
# List all services and status
pm2 list

# Restart a specific service
pm2 restart firecrawl

# Stop a specific service
pm2 stop searxng

# View logs
pm2 logs                    # all services
pm2 logs firecrawl          # single service
pm2 logs firecrawl --lines 50

# Monitor (CPU/memory)
pm2 monit
```

### Add a Service

```bash
node scripts/add.js <name> "<command>" [cwd]
pnpm start
```

### Remove a Service

```bash
node scripts/remove.js <name>
pnpm start
```

### Save PM2 State

After starting/stopping services, save the process list for auto-restart on boot:

```bash
pm2 save
```

### Auto-Start on Boot

PM2 systemd service is configured at `/etc/systemd/system/pm2-phat.service`. On reboot, `pm2 resurrect` starts all saved services.

### Auto-Update (Cron)

Stack auto-updates every 6 hours via `scripts/stack-update.sh`:

- Git services (firecrawl): ff-merge or rebase
- Forks with upstream (harness-cloak): sync upstream first
- CloakBrowser: check for new binary
- Post-update hooks: pnpm install, docker compose up, uv tool install
- Conflict resolution: auto via `dsh headless` from `.conflict-resolve.md`

Manual run:

```bash
~/stack/scripts/stack-update.sh
```

Logs: `~/stack/logs/stack-update.log`

### Service-Specific Setup

Each service has its own README.md and .env.example:

| Service | README | .env.example |
|---------|--------|--------------|
| 9router | [9router/README.md](9router/README.md) | [9router/.env.example](9router/.env.example) |
| portainer | [portainer/README.md](portainer/README.md) | [portainer/.env.example](portainer/.env.example) |
| searxng | [searxng/README.md](searxng/README.md) | [searxng/.env.example](searxng/.env.example) |
| termix | [termix/README.md](termix/README.md) | [termix/.env.example](termix/.env.example) |
| dsh | [dsh/README.md](dsh/README.md) | [dsh/.env.example](dsh/.env.example) |
| firecrawl | [firecrawl/README.md](firecrawl/README.md) | [firecrawl/.env.example](firecrawl/.env.example) |
| cloak-browser | (auto-started) | N/A |
| desktop | [desktop/README.md](desktop/README.md) | N/A — host packages, not a container |


---

## Git Conventions

### Submodules vs Direct Clone

| Type | Example | `.gitmodules` | Update method |
|------|---------|---------------|---------------|
| Submodule | firecrawl | ✅ Registered | `git submodule update --remote` |
| Direct clone | harness-cloak | ❌ | `git pull` in directory |

### Fork vs Upstream

| Service | Repo | Fork? | Upstream tracking |
|---------|------|-------|-------------------|
| firecrawl | nmphat/firecrawl | ✅ fork | ❌ no upstream remote |
| harness-cloak | nmphat/harness-cloak | ✅ fork | ✅ upstream = browser-use/browser-harness |

### Branch Conventions

| Service | Branch | Why |
|---------|--------|-----|
| firecrawl | stack-customizations | our PM2 + playwright changes |
| harness-cloak | cloak | our CloakBrowser integration |

---

## Auto-Update System

### Architecture

```
stack-update.sh (cron every 6h)
  │
  ├─ For each git service:
  │   1. git fetch origin
  │   2. git merge --ff-only origin/<branch>
  │   3. If ff fails → git rebase origin/<branch>
  │   4. If rebase conflicts → abort + dsh headless fallback
  │   5. Post-update hooks (pnpm install, uv tool install, docker compose up)
  │   6. PM2 restart
  │
  ├─ For forks with upstream (harness-cloak):
  │   1. git fetch upstream main
  │   2. git rebase upstream/main (before origin merge)
  │   3. If conflict → same fallback flow
  │
  ├─ CloakBrowser binary (not git):
  │   1. cloakbrowser update (check + download new Chromium)
  │   2. If updated → PM2 restart cloak-browser
  │   3. start-cloak-browser.sh resolves binary path dynamically
  │
  └─ Structured report → logs/stack-update.log
```

### Conflict Resolution

When rebase fails, `stack-update.sh` reads `.conflict-resolve.md` for per-service prompts and calls `dsh headless` automatically.

**Principle: Source of truth = upstream repo.**

Each service has its own resolution prompt with:
- Source of truth declaration
- List of custom files to PRESERVE
- Specific merge rules
- Post-resolution verification command

See `.conflict-resolve.md` for full prompts.

### Cron Job

```
Name: stack-auto-update
Schedule: 0 */6 * * * (every 6h)
Workdir: ~/stack
Skill: systematic-debugging
Delivery: local (save to file)
```

### Manual Run

```bash
~/stack/scripts/stack-update.sh
```

---

## harness-cloak (Browser Harness + CloakBrowser)

### What it is

Fork of `browser-use/browser-harness` (14.8k stars) with CloakBrowser stealth mode.

```
CloakBrowser (stealth Chromium, 58 anti-detection patches)
    ↓ CDP WS
harness-cloak daemon (browser-harness fork)
    ↓ IPC
helpers.py + agent_helpers.py + domain-skills/
    ↓
agent (terminal tool, or any CDP client on 9222)
```

### Our customizations (branch `cloak`)

| File | Change |
|------|--------|
| `src/browser_harness/cloak.py` | NEW — CloakBrowser auto-launcher |
| `src/browser_harness/daemon.py` | +2 lines — ensure_cloak_browser() + shutdown |
| `src/browser_harness/run.py` | +8 lines — --cloak flag + HELP text |
| `pyproject.toml` | renamed to harness-cloak, added cloak extras |
| `agent-workspace/domain-skills/cloakbrowser/` | NEW — anti-detection skill |

### Upstream sync

```bash
cd ~/stack/harness-cloak
./sync-upstream.sh  # manual
# OR: stack-update.sh handles it automatically (every 6h)
```

### Usage

```bash
# CloakBrowser auto-starts via PM2 on CDP port 9222

# Via CDP (Layer 1 — automatic)
# Point the agent's browser tools at http://127.0.0.1:9222 and they drive
# CloakBrowser directly — no per-call command.

# Via CLI (Layer 2 — advanced, self-healing)
BU_CDP_URL=http://127.0.0.1:9222 harness-cloak <<'PY'
new_tab("https://protected-site.com")
wait_for_load()
print(page_info())
PY

# With --cloak flag (auto-launch CloakBrowser if not running)
harness-cloak --cloak <<'PY'
new_tab("https://example.com")
wait_for_load()
PY
```

### Bot detection bypass

CloakBrowser passes all 20/20 detection signals:
Cloudflare Turnstile, reCAPTCHA v3, DataDome, PerimeterX, Akamai, FingerprintJS, etc.

---

## CloakBrowser (Stealth Chromium)

- Binary: `~/.cloakbrowser/chromium-146.0.7680.177.5/chrome`
- Manager: `cloakbrowser` CLI (install/info/update/clear-cache)
- MCP server: `cloakbrowsermcp` (separate from harness-cloak)
- PM2 service: `cloak-browser` → CDP on port 9222
- Profile: `~/.cloakbrowser/profiles/default/`

---

## Cloudflare Tunnels

| Domain | Service | Port |
|--------|---------|------|
| router.3p.id.vn | 9router | 20128 |
| portainer.3p.id.vn | portainer | 9000 |
| dsh.3p.id.vn | dsh | 3080 |

Not exposed: searxng (:8888), termix (:5674), cloak-browser (:9222)

---

## Verification Results (2026-06-14)

### Bot Detection Test

Agent `browser_*` tools via CDP → CloakBrowser:
```json
{"isBot": false, "hasBotUserAgent": false, "hasWebdriverTrue": false, "isPlaywright": false, "hasInconsistentChromeObject": false, "isHeadlessChrome": false, "isAutomatedWithCDP": false, ...}
```
20/20 signals = false. "You are human!"

### Comparison: Playwright vs CDP browser tools vs harness-cloak

| | Playwright (default) | CDP browser tools | harness-cloak |
|---|---|---|---|
| Bot detection | ❌ Detected | ✅ Undetected | ✅ Undetected |
| Cloudflare | ❌ Blocked | ✅ Passes | ✅ Passes |
| Accessibility tree | ✅ | ✅ | ❌ (screenshots) |
| Raw CDP | ❌ | ❌ | ✅ |
| Self-healing | ❌ | ❌ | ✅ |
| Domain skills | ❌ | ❌ | ✅ 100+ sites |

### Usage Recommendation

| Scenario | Use |
|---|---|
| Normal browsing | CDP browser tools (fast, ref-based) |
| Bot-protected sites | CDP browser tools (→ CloakBrowser) |
| Raw CDP / network intercept | harness-cloak via terminal |
| Complex sites, self-healing | harness-cloak + domain skills |

---

## Structure

```
stack/
├── scripts/
│   ├── start.js                  # PM2 service launcher (services.json)
│   ├── add.js                    # Add a service to services.json
│   ├── remove.js                 # Remove a service
│   ├── 9router.sh                # Router startup
│   ├── start-cloak-browser.sh    # CloakBrowser PM2 startup
│   └── stack-update.sh           # Auto-update with dsh fallback
├── services.json                 # Service definitions (PM2)
├── setup.sh                      # First-run setup (submodule init + pnpm install)
├── .conflict-resolve.md          # Per-service conflict resolution prompts
├── .gitmodules                   # Submodule definitions
├── README.md                     # This file
│
├── firecrawl/                    # [submodule] nmphat/firecrawl (stack-customizations)
│   ├── pm2-start.sh              # PM2 launcher
│   └── docker-compose.override.yaml # Stack-specific overrides
│
├── harness-cloak/                # [clone] nmphat/harness-cloak (cloak branch)
│   ├── src/browser_harness/      # Core harness code
│   ├── sync-upstream.sh          # Manual upstream sync
│   └── agent-workspace/          # Domain skills + agent helpers
│
│
├── portainer/                    # Docker compose config
├── searxng/                      # Docker compose + settings
├── termix/                       # Docker compose config
├── dsh/                         # DeepSeek Harness Web UI (npm, systemd user unit)
├── n8n/                          # Docker compose config
├── logs/                         # PM2 logs (gitignored)
└── data/                         # Runtime data (gitignored)
```
