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

Hermes ships no per-project bank selection. Every other Hindsight integration
(codex, cursor, copilot-cli, zcode) has `dynamicBankId`; the Hermes provider
only has a single `bank_id`, so without this every project shares one bank.
Upstream PR #97620 adds `{workspace}` resolution and `.hindsight/config.toml`,
but it is unmerged -- that TOML file does nothing today.

Two things are worth knowing before configuring it:

**The provider does not read `config.yaml`.** `memory.hindsight.*` there is only
what `hermes memory status` prints. The plugin calls `_load_config()`, which
reads `$HERMES_HOME/hindsight/config.json`, else `~/.hindsight/config.json`,
else the environment. So `bank_id` and `bank_id_template` in `config.yaml` have
no effect at runtime, and `HINDSIGHT_BANK_ID` is the lever that works.

**Creating a `config.json` disables that lever.** The env branch is only reached
when neither JSON file exists, so keep the configuration in `~/.hermes/.env`:

```
HINDSIGHT_MODE=local_external
HINDSIGHT_API_URL=http://127.0.0.1:8890
HINDSIGHT_API_KEY=<tenant key>
HINDSIGHT_LLM_API_KEY=<any non-empty value; the server owns the LLM call>
HINDSIGHT_API_LLM_OUTPUT_LANGUAGE=English
```

Then derive the bank from the working directory. This belongs **above** the
`# If not running interactively, don't do anything` return in `~/.bashrc`, or
`bash -lc hermes` never sees the function:

```bash
hermes() {
    local root
    # A submodule's toplevel is the submodule; ask for the superproject first
    # so ~/stack/firecrawl is still bank-stack.
    root=$(git -C "$PWD" rev-parse --show-superproject-working-tree 2>/dev/null)
    [ -n "$root" ] || root=$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null)
    [ -n "$root" ] || root=$PWD
    local slug
    slug=$(basename "$root" | tr -c 'A-Za-z0-9_-' '-' | sed 's/^-*//; s/-*$//')
    HINDSIGHT_BANK_ID="bank-${slug}" command hermes "$@"
}
```

| Working directory | Bank |
|---|---|
| `~/project-badminton` | `bank-project-badminton` |
| `~/stack` | `bank-stack` |
| `~/stack/firecrawl` | `bank-stack` |

Systemd services do not source `.bashrc`, so hermes-webui falls back to the
plugin default bank. Set `HINDSIGHT_BANK_ID` in its unit if it should differ.

`HINDSIGHT_API_LLM_OUTPUT_LANGUAGE` is not cosmetic: mimo extracts facts in
Chinese by default, and recall matches stored text against the query, so mixed
languages quietly cost retrieval accuracy.
