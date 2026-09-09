# Beszel

Resource monitoring for the VPS: CPU, memory, disk and network as percentages,
per-container stats, and alerts. Two containers — the hub serves the dashboard,
the agent collects from the host.

Watch this one specifically for Oracle's idle reclamation. A free-tier instance
is eligible to be reclaimed when, over a 7-day window, its 95th-percentile CPU
is under 20% **and** network is under 20% **and** memory is under 20%. Beszel
graphs all three.

## Setup

```bash
cp .env.example .env
docker compose up -d beszel        # hub first — the agent needs a token from it
```

Create the login from the CLI rather than through the first-run web form:

```bash
docker exec beszel /beszel superuser create <email> <password>
```

That account is the PocketBase admin at `/_/`. The dashboard itself logs in
against the `users` collection, so add one:

```bash
T=$(curl -s -X POST localhost:8090/api/collections/_superusers/auth-with-password \
     -H 'Content-Type: application/json' \
     -d '{"identity":"<email>","password":"<password>"}' | jq -r .token)

curl -s -X POST localhost:8090/api/collections/users/records \
  -H "Authorization: $T" -H 'Content-Type: application/json' \
  -d '{"email":"<email>","password":"<pw>","passwordConfirm":"<pw>","verified":true,"role":"admin"}'
```

Then pair the agent. The token endpoint refuses superusers, so authenticate as
the dashboard user:

```bash
U=$(curl -s -X POST localhost:8090/api/collections/users/auth-with-password \
     -H 'Content-Type: application/json' \
     -d '{"identity":"<email>","password":"<pw>"}' | jq -r .token)

curl -s "localhost:8090/api/beszel/universal-token?enable=1" -H "Authorization: $U"   # TOKEN
curl -s localhost:8090/api/beszel/getkey -H "Authorization: $U"                       # KEY
```

Put both in `.env`, `docker compose up -d`, and turn the token off again once
the agent shows up — it exists only to let a new agent register:

```bash
curl -s "localhost:8090/api/beszel/universal-token?enable=0" -H "Authorization: $U"
```

## Ports

| Port | Description |
|------|-------------|
| 8090 | Hub dashboard, bound to `127.0.0.1` |

The agent opens no port at all: it listens on a unix socket in the
`beszel_socket` volume that the hub shares.

## Security

`USER_CREATION=false` closes the open sign-up form. Without it, the first
stranger to load the page after the hostname resolves can create an account.
Verify it is closed:

```bash
curl -s -X POST https://oc-cp.3p.id.vn/api/collections/users/records \
  -H 'Content-Type: application/json' \
  -d '{"email":"x@example.com","password":"aaaaaaaaaaaa","passwordConfirm":"aaaaaaaaaaaa"}'
# {"message":"Only superusers can perform this action.","status":403}
```

The docker socket is mounted read-only — container stats, no control.

## Cloudflare Tunnel

```bash
sudo tunnel add oc-cp 8090
```

`APP_URL` in the compose file must match the hostname you actually reach it on,
or generated links point somewhere wrong.

## Update

```bash
docker compose pull && docker compose up -d
```
