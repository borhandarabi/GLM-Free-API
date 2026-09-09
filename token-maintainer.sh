#!/usr/bin/env bash
set -Eeuo pipefail

APP_DIR="/app"
STATE_DIR="${TOKEN_STATE_DIR:-/var/lib/zai-api}"
LAST_RUN_FILE="${STATE_DIR}/token-collector.last-run"
LAST_CHECK_FILE="${STATE_DIR}/health.last-check"
LOCK_FILE="${STATE_DIR}/token-maintainer.lock"

PORT="${PORT:-3001}"
HOST="${HEALTH_HOST:-127.0.0.1}"
HEALTH_CHECK_INTERVAL_MINUTES="${HEALTH_CHECK_INTERVAL_MINUTES:-5}"
TOKEN_MIN_COUNT="${TOKEN_MIN_COUNT:-1000}"
TOKEN_REFRESH_AFTER_MINUTES="${TOKEN_REFRESH_AFTER_MINUTES:-30}"
TOKEN_COLLECTOR_RETRY_DELAY_SECONDS="${TOKEN_COLLECTOR_RETRY_DELAY_SECONDS:-30}"

mkdir -p "$STATE_DIR"

run_collector_with_retry() {
    while true; do
        echo "[token-maintainer] running token collector"
        if "$APP_DIR/token-collector" --tokens 850 --batch 4 --no-tui --parallel 1; then
            date +%s > "$LAST_RUN_FILE"
            echo "[token-maintainer] token collector completed successfully"
            return 0
        fi

        echo "[token-maintainer] token collector failed; retrying in ${TOKEN_COLLECTOR_RETRY_DELAY_SECONDS}s" >&2
        sleep "$TOKEN_COLLECTOR_RETRY_DELAY_SECONDS"
    done
}

if [[ "${1:-}" == "--collect" ]]; then
    run_collector_with_retry
    exit 0
fi

exec 9>"$LOCK_FILE"
if ! flock -n 9; then
    exit 0
fi

now="$(date +%s)"
last_check=0
if [[ -s "$LAST_CHECK_FILE" ]]; then
    last_check="$(cat "$LAST_CHECK_FILE")"
fi

if (( last_check > 0 && now - last_check < HEALTH_CHECK_INTERVAL_MINUTES * 60 )); then
    exit 0
fi
printf '%s\n' "$now" > "$LAST_CHECK_FILE"

health_json=""
if ! health_json="$(curl --fail --silent --show-error --max-time 15 "http://${HOST}:${PORT}/health")"; then
    echo "[token-maintainer] health request failed; starting collector retry loop" >&2
    run_collector_with_retry
    exit 0
fi

healthy="$(printf '%s' "$health_json" | sed -n 's/.*"healthy"[[:space:]]*:[[:space:]]*\(true\|false\).*/\1/p')"
token_count="$(printf '%s' "$health_json" | sed -n 's/.*"tokenCount"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p')"

if [[ "$healthy" != "true" || -z "$token_count" ]]; then
    echo "[token-maintainer] invalid/unhealthy response: $health_json" >&2
    run_collector_with_retry
    exit 0
fi

last_run=0
if [[ -s "$LAST_RUN_FILE" ]]; then
    last_run="$(cat "$LAST_RUN_FILE")"
fi

if (( last_run == 0 || now - last_run >= TOKEN_REFRESH_AFTER_MINUTES * 60 )); then
    echo "[token-maintainer] refresh interval reached (${TOKEN_REFRESH_AFTER_MINUTES}m)"
    run_collector_with_retry
elif (( token_count < TOKEN_MIN_COUNT )); then
    echo "[token-maintainer] tokenCount=${token_count} is below minimum=${TOKEN_MIN_COUNT}"
    run_collector_with_retry
else
    echo "[token-maintainer] healthy=true tokenCount=${token_count}; no refresh needed"
fi
