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
| `oc-hindsight.3p.id.vn` | Control Plane UI (:9991) |

The MCP API on 8890 is not published. Reach it over the SSH tunnel instead:
`ssh -N -L 8890:localhost:8890 <host>`.

## Troubleshooting

### HSUI "failed to fetch bank"

Ensure `HINDSIGHT_CP_DATAPLANE_API_KEY` is set (same value as `HINDSIGHT_API_TENANT_API_KEY`).

### LLM errors

Check `HINDSIGHT_API_LLM_API_KEY` is valid. For local LLM: set provider to `llamacpp` and model will auto-download.

### "Fact extraction failed: N/N chunks failed", logs say `missing 'what' field`

The model never saw the schema. Hindsight appends it to the **system** message,
and some providers behind 9router drop that role entirely. Every Qoder (`qd/*`)
model does, including one wrapped in a 9router combo -- the combo only routes,
and the provider adapter below it is what flattens the messages. BYOK providers
keep the system message.

Screen a model before pointing Hindsight at it:

```bash
curl -s $BASE_URL/chat/completions -H "Authorization: Bearer $KEY" \
  -H 'Content-Type: application/json' \
  -d '{"model":"MODEL","stream":false,"messages":[
       {"role":"system","content":"Always reply with exactly the word BANANA, nothing else."},
       {"role":"user","content":"What is the capital of France?"}]}'
```

`BANANA` means the system role survives. An answer about Paris means it does not.

### `PermissionDeniedError: Your request was blocked.`

Cloudflare in front of the 9router endpoint rejects the OpenAI SDK's
User-Agent. Override it:

```
HINDSIGHT_API_LLM_DEFAULT_HEADERS={"User-Agent": "curl/8.5.0"}
```

## Per-project memory banks (Hermes)

Stock Hermes has no per-project bank: every other Hindsight integration exposes
`dynamicBankId`, the Hermes provider only has one `bank_id`, so all projects
share one memory. This box carries upstream PR #97620 (unmerged) to fix it —
see "Keeping the patch" below.

### How to use it

Drop one file at the root of a project:

```toml
# <project>/.hindsight/config.toml
bank_id = "bank-<project>"
```

The provider walks up from the session's working directory and takes the
closest one, so a subdirectory — including a git submodule — inherits its
parent's bank. Nothing else to configure.

| Working directory | Bank |
|---|---|
| `~/stack` | `bank-stack` |
| `~/stack/firecrawl` | `bank-stack` (inherited) |
| `~/project-badminton` | `bank-project-badminton` |
| `~` | falls back to the static `bank_id` |

Full precedence, highest first: `--hindsight-bank` flag → closest
`.hindsight/config.toml` → `bank_id_template` → static `bank_id`.

### Why the TOML and not the template

The PR also makes `{workspace}` in `bank_id_template` resolve to a real project
slug, but it reads that slug from the projects registry in `projects.db`, and
this build ships no `hermes projects` command to populate it. With an empty
registry `{workspace}` renders empty, so the TOML is the lever that works here.

### It works in the WebUI too

The WebUI runs the agent in-process, and its per-session workspace never
becomes the process working directory — so a shell wrapper cannot reach it.
What does reach it: before each run the WebUI sets `TERMINAL_CWD` to the
session's workspace (`api/streaming.py`), and `resolve_agent_cwd()` — the same
function the TOML walk-up starts from — reads `TERMINAL_CWD` ahead of
`os.getcwd()`. Verified by running from `~` with only `TERMINAL_CWD` pointing
elsewhere: the memory landed in that directory's bank.

One caveat, which is the WebUI's design and not this patch: `TERMINAL_CWD` is
process-global and the lock is released before the agent runs, so two sessions
on different workspaces started at the same instant can in principle read each
other's value.

### What does not work

`AGENTS.md` cannot do this. The bank is chosen when the provider initialises,
before the model sees any prompt, and neither `hindsight_recall` nor
`hindsight_retain` takes a bank argument — so no instruction can move it.

`memory.hindsight.*` in `~/.hermes/config.yaml` is only what
`hermes memory status` prints. The provider calls `_load_config()`, which reads
`$HERMES_HOME/hindsight/config.json`, else `~/.hindsight/config.json`, else the
environment. Setting `bank_id` there changes nothing at runtime.

Creating either `config.json` switches off the environment branch, so keep the
connection settings in `~/.hermes/.env`:

```
HINDSIGHT_MODE=local_external
HINDSIGHT_API_URL=http://127.0.0.1:8890
HINDSIGHT_API_KEY=<tenant key>
HINDSIGHT_LLM_API_KEY=<any non-empty value; the server owns the LLM call>
HINDSIGHT_API_LLM_OUTPUT_LANGUAGE=English
```

The last one is not cosmetic: mimo extracts facts in Chinese by default, and
recall matches stored text against the query, so a mixed-language bank loses
accuracy with no visible error.

### Keeping the patch

`~/.hermes/hermes-agent` is on branch `hindsight-per-project`: upstream commit
`26128052ac` cherry-picked onto `72a3277cd7`. It applied without conflicts.

`hermes update` pulls, so it will now hit a divergent branch. When PR #97620
merges, drop the patch instead of merging it:

```bash
cd ~/.hermes/hermes-agent
git checkout main && git pull && git branch -D hindsight-per-project
```

Optional CLI convenience, for directories with no `.hindsight/config.toml`.
It must go **above** the `# If not running interactively` return in `.bashrc`,
or `bash -lc hermes` never sees it:

```bash
hermes() {
    local root
    root=$(git -C "$PWD" rev-parse --show-superproject-working-tree 2>/dev/null)
    [ -n "$root" ] || root=$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null)
    [ -n "$root" ] || root=$PWD
    local slug
    slug=$(basename "$root" | tr -c 'A-Za-z0-9_-' '-' | sed 's/^-*//; s/-*$//')
    HINDSIGHT_BANK_ID="bank-${slug}" command hermes "$@"
}
```
