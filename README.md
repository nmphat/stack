# Stack

Homelab service orchestrator. PM2 manages all services via `pnpm start`.

## Services

| Service | Type | Port | Source | Git | Update |
|---------|------|------|--------|-----|--------|
| 9router | CLI | 20128 | `scripts/9router.sh` | — | manual |
| portainer | Docker | 9000 | `portainer/` | — | `docker compose pull` |
| searxng | Docker | 8888 | `searxng/` | — | `docker compose pull` |
| hermes-gateway | CLI | — | `hermes gateway` | — | `hermes update` |
| hindsight | Docker | 8890 | `hindsight/` | — | `docker compose pull` |
| termix | Docker | 5674 | `termix/` | — | `docker compose pull` |
| hermes-webui | Git | 8787 | `hermes-webui/` | submodule nesquena/master | `stack-update.sh` |
| firecrawl | Git+Docker | 3092 | `firecrawl/` | submodule nmphat/stack-customizations | `stack-update.sh` |
| open-design | Git | 7456 | `open-design/` | repo nexu-io/main | `stack-update.sh` |
| **cloak-browser** | **PM2** | **9222** | **`scripts/start-cloak-browser.sh`** | — | **auto via stack-update.sh** |

## Quick Start

```bash
git clone --recurse-submodules git@github.com:nmphat/stack.git
cd stack
./setup.sh
pnpm start
```

## Adding a Service

```bash
node scripts/add.js <name> "<command>" [cwd]
pnpm start
```

---

## Git Conventions

### Submodules vs Direct Clone

| Type | Example | `.gitmodules` | Update method |
|------|---------|---------------|---------------|
| Submodule | hermes-webui, firecrawl | ✅ Registered | `git submodule update --remote` |
| Direct clone | harness-cloak, open-design | ❌ | `git pull` in directory |

### Fork vs Upstream

| Service | Repo | Fork? | Upstream tracking |
|---------|------|-------|-------------------|
| hermes-webui | nesquena/hermes-webui | ❌ upstream repo | N/A — pull directly |
| firecrawl | nmphat/firecrawl | ✅ fork | ❌ no upstream remote |
| harness-cloak | nmphat/harness-cloak | ✅ fork | ✅ upstream = browser-use/browser-harness |
| open-design | nexu-io/open-design | ❌ upstream repo | N/A — pull directly |

### Branch Conventions

| Service | Branch | Why |
|---------|--------|-----|
| hermes-webui | master | follows upstream |
| firecrawl | stack-customizations | our PM2 + playwright changes |
| harness-cloak | cloak | our CloakBrowser integration |
| open-design | main | follows upstream |

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
  │   4. If rebase conflicts → abort + Hermes agent fallback
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

When rebase fails, `stack-update.sh` reads `.conflict-resolve.md` for per-service prompts and calls Hermes agent automatically.

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
Hermes agent (via terminal tool or browser.cdp_url)
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

# Via Hermes config (Layer 1 — automatic)
hermes config set browser.cdp_url "http://127.0.0.1:9222"
# browser_navigate, browser_snapshot, browser_click use CloakBrowser directly

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
| hsui.3p.id.vn | Hindsight CP UI | 9991 |
| hs.3p.id.vn | Hindsight MCP | 8890 |
| hermes.3p.id.vn | hermes-webui | 8787 |
| od.3p.id.vn | open-design | 7456 |

Not exposed: searxng (:8888), termix (:5674), cloak-browser (:9222)

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
│   └── stack-update.sh           # Auto-update with Hermes fallback
├── services.json                 # Service definitions (PM2)
├── setup.sh                      # First-run setup (submodule init + pnpm install)
├── .conflict-resolve.md          # Per-service conflict resolution prompts
├── .gitmodules                   # Submodule definitions
├── README.md                     # This file
│
├── hermes-webui/                 # [submodule] nesquena/hermes-webui (master)
│   ├── pm2-start.sh              # PM2 launcher (untracked)
│   └── .env                      # Secrets (gitignored)
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
├── open-design/                  # [clone] nexu-io/open-design (main)
│
├── portainer/                    # Docker compose config
├── searxng/                      # Docker compose + settings
├── hindsight/                    # Docker compose config
├── termix/                       # Docker compose config
├── logs/                         # PM2 logs (gitignored)
└── data/                         # Runtime data (gitignored)
```
