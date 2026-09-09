#!/usr/bin/env bash
set -e
exec 2>&1
cd /app
export PORT="${PORT:-3001}"
export HOST="${HOST:-0.0.0.0}"
export TIMEOUT="${TIMEOUT:-300000}"
export AUTH_TOKEN="${AUTH_TOKEN:-Waguri}"
export ZAI_TOKEN="${ZAI_TOKEN:-}"
export AGENT_MODE="${AGENT_MODE:-true}"
export AGENT_MODE_VARIANT="${AGENT_MODE_VARIANT:-modern}"
export STREAM_HOLDBACK="${STREAM_HOLDBACK:-24}"
export LOG_LEVEL="${LOG_LEVEL:-info}"
export SYNC_MODE="${SYNC_MODE:-false}"
export SESSION_POOL_SIZE="${SESSION_POOL_SIZE:-5}"
export UPSTREAM_MIN_INTERVAL_MS="${UPSTREAM_MIN_INTERVAL_MS:-200}"
export SESSION_ACQUIRE_TIMEOUT="${SESSION_ACQUIRE_TIMEOUT:-10}"
export LOG_FORMAT="${LOG_FORMAT:-text}"
export HEALTH_CHECK_INTERVAL_MINUTES="${HEALTH_CHECK_INTERVAL_MINUTES:-5}"
export TOKEN_MIN_COUNT="${TOKEN_MIN_COUNT:-1000}"
export TOKEN_REFRESH_AFTER_MINUTES="${TOKEN_REFRESH_AFTER_MINUTES:-30}"
export TOKEN_COLLECTOR_RETRY_DELAY_SECONDS="${TOKEN_COLLECTOR_RETRY_DELAY_SECONDS:-30}"

/usr/local/bin/token-maintainer.sh --collect

cat > /etc/cron.d/token-maintainer <<EOF
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
HEALTH_CHECK_INTERVAL_MINUTES=${HEALTH_CHECK_INTERVAL_MINUTES}
TOKEN_MIN_COUNT=${TOKEN_MIN_COUNT}
TOKEN_REFRESH_AFTER_MINUTES=${TOKEN_REFRESH_AFTER_MINUTES}
TOKEN_COLLECTOR_RETRY_DELAY_SECONDS=${TOKEN_COLLECTOR_RETRY_DELAY_SECONDS}
PORT=${PORT}
HEALTH_HOST=127.0.0.1

* * * * * root /usr/local/bin/token-maintainer.sh >> /var/log/token-maintainer.log 2>&1
EOF
chmod 0644 /etc/cron.d/token-maintainer
cron

exec ./zai-api
