# Hindsight

AI memory engine. Provides persistent memory for Hermes Agent via MCP protocol.

## Setup

```bash
# Copy and edit env file
cp .env.example .env
vim .env

# Start
docker compose up -d
```

### Required Environment Variables

| Variable | Description |
|----------|-------------|
| `HINDSIGHT_API_LLM_PROVIDER` | LLM provider (openai, openrouter, llamacpp) |
| `HINDSIGHT_API_LLM_API_KEY` | API key for LLM provider |
| `HINDSIGHT_API_TENANT_API_KEY` | Tenant auth key (generate: `openssl rand -base64 32`) |
| `HINDSIGHT_API_MCP_AUTH_TOKEN` | MCP auth token |
| `HINDSIGHT_CP_ACCESS_KEY` | Control Plane UI login key (format: `hs_cp_...`) |
| `HINDSIGHT_CP_DATAPLANE_API_KEY` | Same as TENANT_API_KEY (used by HSUI backend) |

## Ports

| Port | Protocol | Description |
|------|----------|-------------|
| 8890 | HTTP | MCP API endpoint |
| 9991 | HTTP | Control Plane UI (HSUI) |

## Data

Persistent volume: `hindsight_data` -> `/home/hindsight/.pg0`

## Update

```bash
docker compose pull
docker compose up -d
```

## Cloudflare Tunnel

| Domain | Service |
|--------|---------|
| `hs.3p.id.vn` | MCP API (:8890) |
| `hsui.3p.id.vn` | Control Plane UI (:9991) |

## Troubleshooting

### HSUI "failed to fetch bank"

Ensure `HINDSIGHT_CP_DATAPLANE_API_KEY` is set (same value as `HINDSIGHT_API_TENANT_API_KEY`).

### LLM errors

Check `HINDSIGHT_API_LLM_API_KEY` is valid. For local LLM: set provider to `llamacpp` and model will auto-download.
