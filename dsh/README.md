# dsh (DeepSeek Harness Web UI)

[deepseek-ai/deepseek-harness](https://github.com/deepseek-ai/deepseek-harness)
installed from npm as a persistent service on the Oracle box.

| | |
|---|---|
| Port | `3080` (loopback) |
| Tunnel | `oc-dsh.3p.id.vn` |
| Supervisor | systemd user unit `dsh-web.service` |
| Home | `~/.dsh` (profiles, sessions, settings) |

## Install / update

```bash
cd ~/stack/dsh
npm install                      # installs the pinned version
npm update @deepseek-ai/dsh      # bump within the pinned range
systemctl --user restart dsh-web
```

## Service

```bash
systemctl --user status dsh-web
systemctl --user restart dsh-web
journalctl --user -u dsh-web -f
```

The startup log prints the entry URL including the launch token. The token is a
process credential: it exchanges for a signed session cookie, so keep it private
and do not paste it into shared channels.

## Tunnel

```bash
sudo tunnel add oc-dsh 3080
sudo tunnel list
```

`dsh web` binds `127.0.0.1`; only `cloudflared` reaches it. `--trusted-host`
admits the public authority, and the Web UI's own token/cookie auth gates access.

## API key

The Web UI's model route is the stack's own gateway, not the DeepSeek SaaS
endpoint: provider `oc-9router`, base URL `http://localhost:20128/v1`, model
`cmd/deepseek/deepseek-v4.1-flash`. Its key lives in `~/stack/dsh/.env` as
`OC_9ROUTER_API_KEY`, which the systemd unit loads and the headless profile
reads via `apiKeyEnv`. Get the value from 9router's dashboard.

`~/.dsh/.credentials.yaml` is the UI's own credential store; it is not consulted
by `dsh headless`, so the env file is what makes both paths work.

## Headless

`~/.dsh/profiles/headless/cordis.patch.yml` carries the same provider and
default-model patch as the web profile. Without it `dsh headless` falls back to
the `deepseek-official` route and fails with `MISSING_CREDENTIAL`.

```bash
set -a; . ~/stack/dsh/.env; set +a
~/stack/dsh/node_modules/.bin/dsh headless "reply with exactly: OK"
```

`scripts/stack-update.sh` uses this to resolve rebase conflicts.

