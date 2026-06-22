#!/bin/bash
# stack-update.sh — Auto-update all git-based stack services.
# Exit 0: all clean. Exit 1: conflicts need agent resolution.
# Stdout: structured report for Hermes cron parsing.
#
# Flow per service:
#   1. git fetch + ff-only merge
#   2. If ff fails → git rebase
#   3. If rebase conflicts → abort, report, trigger Hermes agent fallback
#   4. Post-update: rebuild/reinstall if needed, restart PM2 service
#
# Conflict resolution prompts: .conflict-resolve.md

set -euo pipefail
cd ~/stack

CONFLICTS=""
UPDATED=""
UP_TO_DATE=""
ERRORS=""
NEED_RESTART=""
HERMES_FALLBACK=""
LOG_FILE="$HOME/stack/logs/stack-update.log"
RESOLVE_FILE="$HOME/stack/.conflict-resolve.md"
mkdir -p "$(dirname "$LOG_FILE")"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

get_resolve_prompt() {
    local service="$1"
    if [ ! -f "$RESOLVE_FILE" ]; then
        echo ""
        return
    fi
    # Extract prompt for this service from .conflict-resolve.md
    # Format: <service>|<prompt> (multi-line, until next service or EOF)
    awk -v svc="$service" '
        BEGIN { found=0; prompt="" }
        /^[a-z].*\|/ {
            if (found) { printf "%s", prompt; exit }
            split($0, a, "|")
            if (a[1] == svc) { found=1; prompt=a[2]; next }
        }
        found && !/^#/ && !/^$/ { prompt = prompt "\n" $0 }
        END { if (found) printf "%s", prompt }
    ' "$RESOLVE_FILE"
}

update_service() {
    local name="$1"
    local dir="$2"
    local branch="$3"
    local upstream="${4:-}"       # optional: remote name for fork sync
    local post_update="${5:-}"   # optional: command to run after successful update
    local restart_cmd="${6:-pm2 restart $name}"

    log "[$name] checking..."

    if [ ! -d "$dir/.git" ] && [ ! -f "$dir/.git" ]; then
        ERRORS="$ERRORS $name:not_git"
        log "[$name] ERROR: not a git repo"
        return
    fi

    cd "$dir"

    # Stash any local changes
    local stashed=0
    if ! git diff --quiet 2>/dev/null || ! git diff --cached --quiet 2>/dev/null; then
        git stash push -m "stack-auto-update $(date +%Y%m%d-%H%M%S)" 2>/dev/null && stashed=1
    fi

    # Fetch origin
    git fetch origin "$branch" 2>/dev/null || true

    # For forks with upstream: sync upstream first
    if [ -n "$upstream" ]; then
        git fetch "$upstream" main 2>/dev/null || true
        local behind_upstream
        behind_upstream=$(git rev-list --count "HEAD..${upstream}/main" 2>/dev/null || echo "0")
        if [ "$behind_upstream" -gt 0 ]; then
            log "[$name] $behind_upstream commits behind upstream — rebasing..."
            if ! git rebase "${upstream}/main" 2>/dev/null; then
                local conflict_files
                conflict_files=$(git diff --name-only --diff-filter=U 2>/dev/null | tr '\n' ',')
                CONFLICTS="$CONFLICTS $name:upstream_rebase:[$conflict_files]"
                HERMES_FALLBACK="$HERMES_FALLBACK $name"
                git rebase --abort 2>/dev/null || true
                log "[$name] UPSTREAM REBASE CONFLICT: $conflict_files"
                cd ~/stack
                return
            fi
            UPDATED="$UPDATED $name:upstream-synced"
        fi
    fi

    # Try fast-forward merge from origin
    local local_hash
    local_hash=$(git rev-parse HEAD)

    if git merge --ff-only "origin/$branch" 2>/dev/null; then
        local new_hash
        new_hash=$(git rev-parse HEAD)
        if [ "$local_hash" != "$new_hash" ]; then
            UPDATED="$UPDATED $name"
            log "[$name] updated (ff-merge)"
        else
            UP_TO_DATE="$UP_TO_DATE $name"
            log "[$name] up-to-date"
        fi
    else
        # FF failed — try rebase
        log "[$name] ff-only failed, trying rebase..."
        if git rebase "origin/$branch" 2>/dev/null; then
            UPDATED="$UPDATED $name:rebased"
            log "[$name] updated (rebased)"
        else
            # Rebase conflict!
            local conflict_files
            conflict_files=$(git diff --name-only --diff-filter=U 2>/dev/null | tr '\n' ',')
            CONFLICTS="$CONFLICTS $name:[$conflict_files]"
            HERMES_FALLBACK="$HERMES_FALLBACK $name"
            git rebase --abort 2>/dev/null || true
            log "[$name] CONFLICT: $conflict_files — queued for Hermes agent resolution"
        fi
    fi

    # Post-update hook (rebuild, reinstall, etc.)
    if echo "$UPDATED" | grep -q "$name"; then
        if [ -n "$post_update" ]; then
            log "[$name] running post-update: $post_update"
            eval "$post_update" 2>&1 | tee -a "$LOG_FILE" || {
                ERRORS="$ERRORS $name:post_update_failed"
                log "[$name] post-update failed"
            }
        fi
        NEED_RESTART="$NEED_RESTART $name"
    fi

    # Pop stash
    if [ "$stashed" -eq 1 ]; then
        git stash pop 2>/dev/null || true
    fi

    cd ~/stack
}

# ─── Update each service ───────────────────────────────────────

# Git-based services (submodules + forks)
update_service "hermes-webui" "hermes-webui" "master" "" \
    "cd ~/stack/hermes-webui && pnpm install 2>/dev/null" \
    "pm2 restart hermes-webui"

update_service "firecrawl" "firecrawl" "stack-customizations" "" \
    "" \
    "cd ~/stack/firecrawl && docker compose up -d --build 2>/dev/null && pm2 restart firecrawl"

update_service "harness-cloak" "harness-cloak" "cloak" "upstream" \
    "uv tool install -e ~/stack/harness-cloak --force 2>/dev/null" \
    "echo skip"  # no PM2 restart needed — daemon auto-starts

update_service "open-design" "open-design" "stack-customizations" "upstream" \
    "" \
    "pm2 restart open-design"

# ─── CloakBrowser binary update (not git-based) ────────────────

log "[cloak-browser] checking binary updates..."
CLOAK_UPDATE=$(/home/phat/.local/share/uv/tools/cloakbrowsermcp/bin/cloakbrowser update 2>&1)
if echo "$CLOAK_UPDATE" | grep -qv "Already up to date"; then
    log "[cloak-browser] binary updated — restarting PM2 service"
    NEED_RESTART="$NEED_RESTART cloak-browser"
    UPDATED="$UPDATED cloak-browser:binary"
else
    UP_TO_DATE="$UP_TO_DATE cloak-browser"
    log "[cloak-browser] binary up-to-date"
fi

# ─── Restart changed services ──────────────────────────────────

for svc in $NEED_RESTART; do
    if [ "$svc" != "skip" ]; then
        log "Restarting $svc..."
        pm2 restart "$svc" 2>/dev/null || true
    fi
done
pm2 save 2>/dev/null || true

# ─── Structured report ─────────────────────────────────────────

echo "---STACK-UPDATE-REPORT---"
echo "UPDATED=$UPDATED"
echo "UP_TO_DATE=$UP_TO_DATE"
echo "CONFLICTS=$CONFLICTS"
echo "ERRORS=$ERRORS"
echo "NEED_RESTART=$NEED_RESTART"
echo "HERMES_FALLBACK=$HERMES_FALLBACK"
echo "---END-REPORT---"

# ─── Hermes agent fallback for conflicts ────────────────────────

if [ -n "$HERMES_FALLBACK" ]; then
    log "Conflicts detected in: $HERMES_FALLBACK"
    log "Triggering Hermes agent for conflict resolution..."

    for svc in $HERMES_FALLBACK; do
        prompt=$(get_resolve_prompt "$svc")
        if [ -z "$prompt" ]; then
            prompt="Git rebase conflict in ~/stack/$svc. Resolve the conflict: cd ~/stack/$svc, inspect conflicted files, prefer source of truth (upstream), preserve local customizations, complete rebase, verify build."
        fi

        log "[$svc] calling Hermes agent..."
        hermes chat -q "$prompt" 2>&1 | tee -a "$LOG_FILE" &
    done

    wait
    log "Hermes agent conflict resolution complete."
    exit 1
fi

exit 0
