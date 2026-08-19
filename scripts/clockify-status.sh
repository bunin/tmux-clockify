#!/usr/bin/env bash
#
# Clockify status for tmux, served from a local cache. The API is polled at most
# once per TTL by a background job; the running timer is rendered from the
# cached start time, so a redraw never touches the network.
#
# State file: "running|idle" / label / start epoch, one per line.

set -u

CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/tmux-clockify"
STATE="$CACHE_DIR/state"
LOCK="$CACHE_DIR/lock"
TTL="${CLOCKIFY_TMUX_TTL:-60}"
STALE_LOCK=120

mkdir -p "$CACHE_DIR"

mtime() { stat -f %m "$1" 2>/dev/null || echo 0; }

refresh() {
    # mkdir is atomic, so it doubles as a single-writer lock.
    if ! mkdir "$LOCK" 2>/dev/null; then
        if [ $(( $(date +%s) - $(mtime "$LOCK") )) -gt "$STALE_LOCK" ]; then
            rm -rf "$LOCK"
        fi
        return
    fi
    trap 'rm -rf "$LOCK"' EXIT

    local json project desc start epoch
    json=$(clockify-cli show -j 2>/dev/null)

    if [ -z "$json" ] || [ "$json" = "[]" ] || [ "$json" = "null" ]; then
        printf 'idle\n\n0\n' > "$STATE.tmp"
    else
        project=$(printf '%s' "$json" | jq -r '.[0].project.name // ""' 2>/dev/null)
        desc=$(printf '%s' "$json" | jq -r '.[0].description // ""' 2>/dev/null)
        start=$(printf '%s' "$json" | jq -r '.[0].timeInterval.start // ""' 2>/dev/null)
        epoch=$(TZ=UTC date -j -f '%Y-%m-%dT%H:%M:%SZ' "$start" +%s 2>/dev/null || echo 0)

        if [ "$epoch" -eq 0 ]; then
            printf 'idle\n\n0\n' > "$STATE.tmp"
        else
            printf 'running\n%s / %s\n%s\n' "$project" "$desc" "$epoch" > "$STATE.tmp"
        fi
    fi

    mv -f "$STATE.tmp" "$STATE"
}

age=$(( $(date +%s) - $(mtime "$STATE") ))
if [ ! -f "$STATE" ] || [ "$age" -ge "$TTL" ]; then
    # Redirecting stdout is what keeps this non-blocking: tmux waits on the pipe.
    ( refresh ) >/dev/null 2>&1 &
fi

[ -f "$STATE" ] || exit 0

{ read -r status; read -r label; read -r epoch; } < "$STATE"
[ "${status:-}" = running ] || exit 0

d=$(( $(date +%s) - epoch ))
[ "$d" -lt 0 ] && d=0

# '#' introduces a format in tmux; double it so project names survive.
printf '%s [%d:%02d:%02d]\n' "${label//#/##}" $(( d / 3600 )) $(( d % 3600 / 60 )) $(( d % 60 ))
