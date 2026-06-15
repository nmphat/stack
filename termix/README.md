# Termix

Web-based terminal and remote desktop client. Provides browser-accessible SSH and VNC connections.

## Setup

No .env file. Config via docker-compose.yml.

```bash
docker compose up -d
```

## Ports

| Port | Protocol | Description |
|------|----------|-------------|
| 5674 | HTTP | Web UI |
| 4822 | TCP | guacd (Guacamole daemon) |

## Architecture

```
termix (web UI) :5674
    |
guacd (guacamole daemon) :4822
```

`guacd` is auto-started via `depends_on` in docker-compose.yml.

## Data

Local volume: `./data` -> `/app/data`

## Update

```bash
docker compose pull
docker compose up -d
```

## Not Exposed via Tunnel

Termix runs localhost only. Access via LAN or SSH tunnel.
