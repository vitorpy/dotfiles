#!/usr/bin/env bash
set -euo pipefail

POWER_ONLINE_FILE="${OPENCLAW_POWER_ONLINE_FILE:-/sys/class/power_supply/ACAD/online}"
POLL_INTERVAL="${OPENCLAW_POWER_POLL_INTERVAL:-5}"
NODE_BIN="/home/vitorpy/.nvm/versions/node/v24.10.0/bin/node"
OPENCLAW_BIN="/home/vitorpy/.nvm/versions/node/v24.10.0/lib/node_modules/openclaw/dist/index.js"
GATEWAY_PID=""

log() {
    printf '%s %s\n' "$(date --iso-8601=seconds)" "$*"
}

on_ac_power() {
    [[ -r "$POWER_ONLINE_FILE" ]] && [[ "$(tr -d '[:space:]' < "$POWER_ONLINE_FILE")" == "1" ]]
}

gateway_running() {
    local running_pid

    [[ -n "$GATEWAY_PID" ]] || return 1

    while read -r running_pid; do
        [[ "$running_pid" == "$GATEWAY_PID" ]] && return 0
    done < <(jobs -pr)

    return 1
}

reap_gateway() {
    local status

    [[ -n "$GATEWAY_PID" ]] || return 0

    status=0
    wait "$GATEWAY_PID" 2>/dev/null || status=$?
    log "OpenClaw gateway exited with status ${status}"
    GATEWAY_PID=""
}

start_gateway() {
    if gateway_running; then
        return 0
    fi

    if [[ -n "$GATEWAY_PID" ]]; then
        reap_gateway
    fi

    log "AC power present; starting OpenClaw gateway"
    "$NODE_BIN" "$OPENCLAW_BIN" gateway --port "${OPENCLAW_GATEWAY_PORT:-18789}" &
    GATEWAY_PID="$!"
}

stop_gateway() {
    if ! gateway_running; then
        [[ -z "$GATEWAY_PID" ]] || reap_gateway
        return 0
    fi

    log "AC power absent; stopping OpenClaw gateway"
    kill "$GATEWAY_PID" 2>/dev/null || true
    reap_gateway
}

shutdown() {
    stop_gateway
    exit 0
}

trap shutdown INT TERM

while true; do
    if on_ac_power; then
        start_gateway
    else
        stop_gateway
    fi

    sleep "$POLL_INTERVAL" &
    wait "$!" || true
done
