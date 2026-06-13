#!/bin/bash
# start-cloak-browser.sh — Launch CloakBrowser headless with CDP for harness-cloak
# Used by PM2 as service "cloak-browser"
# Binary path is resolved dynamically — works after cloakbrowser update

# Find cloakbrowser CLI (uv tool install location)
CLOAKBROWSER_CLI=""
for candidate in \
    "/home/phat/.local/share/uv/tools/cloakbrowsermcp/bin/cloakbrowser" \
    "/home/phat/.local/bin/cloakbrowser" \
    "$(which cloakbrowser 2>/dev/null)"; do
    if [ -n "$candidate" ] && [ -x "$candidate" ]; then
        CLOAKBROWSER_CLI="$candidate"
        break
    fi
done

if [ -z "$CLOAKBROWSER_CLI" ]; then
    echo "ERROR: cloakbrowser CLI not found"
    exit 1
fi

# Get binary path dynamically (resolves after updates)
CLOAK_BINARY=$("$CLOAKBROWSER_CLI" info 2>/dev/null | grep "Binary:" | awk '{print $2}')

if [ -z "$CLOAK_BINARY" ] || [ ! -f "$CLOAK_BINARY" ]; then
    echo "ERROR: CloakBrowser binary not found. Run: $CLOAKBROWSER_CLI install"
    exit 1
fi

CDP_PORT="${CLOAK_CDP_PORT:-9222}"
PROFILE_DIR="${HOME}/.cloakbrowser/profiles/default"
mkdir -p "$PROFILE_DIR"

echo "Starting CloakBrowser $CLOAK_BINARY on CDP port $CDP_PORT..."
exec "$CLOAK_BINARY" \
    --headless=new \
    --remote-debugging-port="$CDP_PORT" \
    --user-data-dir="$PROFILE_DIR" \
    --no-sandbox \
    --disable-gpu \
    --disable-dev-shm-usage \
    --window-size=1920,1080 \
    about:blank
