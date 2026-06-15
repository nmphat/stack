# Portainer

Docker management UI for monitoring and managing containers, images, volumes, and networks.

## Setup

No .env file needed. Config via docker-compose.yml.

```bash
docker compose up -d
```

First visit: create admin user at http://localhost:9000

## Ports

| Port | Protocol | Description |
|------|----------|-------------|
| 9000 | HTTP | Web UI |
| 9443 | HTTPS | Web UI (TLS) |

## Data

Persistent volume: `portainer_data` -> `/data`

## Update

```bash
docker compose pull
docker compose up -d
```

## Cloudflare Tunnel

Accessible at: `portainer.3p.id.vn`
