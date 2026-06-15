# 9router

Local LLM API router. Routes requests to multiple LLM providers via a unified OpenAI-compatible endpoint.

## Setup

No .env file needed. Run via CLI flags:

```bash
9router --port 20128 --host 0.0.0.0
```

Or via PM2 (stack default):

```bash
pnpm start   # starts all stack services including 9router
```

## Ports

| Port | Protocol | Description |
|------|----------|-------------|
| 20128 | HTTP | OpenAI-compatible API endpoint |

## Config

All config via CLI flags. See `9router --help`:

```
-p, --port <port>   Port (default: 20128)
-H, --host <host>   Bind address (default: 0.0.0.0)
-n, --no-browser    Don't open browser
-l, --log           Show server logs
-t, --tray          System tray mode
--skip-update       Skip auto-update check
```

## Update

Manual: `npm update -g 9router`

## Cloudflare Tunnel

Accessible at: `router.3p.id.vn`
