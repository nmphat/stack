# SearXNG

Privacy-respecting metasearch engine. Aggregates results from 70+ search engines without tracking.

## Setup

No .env file. Config via `settings.yml`:

```bash
# Edit search engines, UI settings, etc.
vim settings.yml

# Start
docker compose up -d
```

## Ports

| Port | Protocol | Description |
|------|----------|-------------|
| 8888 | HTTP | Search API + Web UI |

## Config

`settings.yml` is mounted read-only into the container. Key settings:

- `search.formats` -- must include `json` for API access
- `engines` -- enable/disable search engines
- `server.secret_key` -- generate with `openssl rand -hex 32`

## Usage

```bash
# Web UI
open http://localhost:8888

# JSON API
curl "http://localhost:8888/search?q=test&format=json"
```

## Update

```bash
docker compose pull
docker compose up -d
```

## Not Exposed via Tunnel

SearXNG runs localhost only. Use via Hermes `web_search` tool or direct access.
