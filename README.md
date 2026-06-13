# Stack

Homelab service orchestrator. PM2 manages all services via `pnpm start`.

## Services

| Service | Type | Port | Source |
|---------|------|------|--------|
| 9router | CLI | — | `scripts/9router.sh` |
| portainer | Docker | 9000 | `portainer/docker-compose.yml` |
| searxng | Docker | 8888 | `searxng/docker-compose.yml` |
| hermes-gateway | CLI | — | `hermes gateway` |
| hindsight | Docker | 8890 | `hindsight/docker-compose.yml` |
| termix | Docker | 5674 | `termix/docker-compose.yml` |
| hermes-webui | Git submodule | 8789 | `hermes-webui/pm2-start.sh` |
| firecrawl | Git submodule | 3092 | `firecrawl/pm2-start.sh` |

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

## Structure

```
stack/
├── scripts/          # PM2 management scripts
│   ├── start.js      # Start all services
│   ├── add.js        # Add a service
│   └── remove.js     # Remove a service
├── services.json     # Service definitions
├── setup.sh          # First-run setup
├── hermes-webui/     # [submodule] Web UI
├── firecrawl/        # [submodule] Web scraper API (customized fork)
├── portainer/        # Docker compose config
├── searxng/          # Docker compose + settings
├── hindsight/        # Docker compose config
├── termix/           # Docker compose config
└── logs/             # PM2 logs (gitignored)
```

## Updating Submodules

```bash
# Pull latest for all submodules
git submodule update --remote

# Pull latest for one
git submodule update --remote hermes-webui
```
