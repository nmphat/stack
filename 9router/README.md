# 9router
Local LLM API router. Routes requests to multiple LLM providers via a unified OpenAI-compatible endpoint.
## Setup
Runs as Docker Compose, with a `headroom` sidecar it proxies through.
```bash
cp .env.example .env    # then fill in the four secrets
docker compose up -d
```
Generate the secrets once; never commit the real `.env`:
```bash
openssl rand -hex 32    # JWT_SECRET, API_KEY_SECRET
openssl rand -hex 16    # MACHINE_ID_SALT, INITIAL_PASSWORD
```
`BASE_URL` must match the address you actually reach the UI on, otherwise
login redirects break.
## Ports
| Port | Protocol | Description |
|------|----------|-------------|
| 20128 | HTTP | Web dashboard + OpenAI-compatible API endpoint |
`headroom` listens on 8787 inside the compose network only.
## Update
```bash
docker compose pull && docker compose up -d
```
## Cloudflare Tunnel
Not exposed by default. To publish it:
```bash
sudo tunnel add oc-9router 20128
```
Every hostname on this VPS is prefixed `oc-`.
