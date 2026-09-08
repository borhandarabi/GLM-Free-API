FROM golang:1.26-bookworm AS zai-builder

WORKDIR /src

COPY . .
# The repository may intentionally omit Go module files; create them in the build.
RUN if [ ! -f go.mod ]; then go mod init zai-api; fi \
    && go mod tidy
# main.go is the actual service entry point.
RUN mkdir -p /app \
    && go build -o /app/token-collector -trimpath -gcflags="all=-l=4" -ldflags="-s -w" ./cmd/token-collector \
    && go build -o /app/zai-api -trimpath -gcflags="all=-l=4" -ldflags="-s -w" .

FROM node:20-bookworm-slim AS zai-runtime

ENV PORT="3001" \
    HOST="0.0.0.0" \
    TIMEOUT="300000" \
    AUTH_TOKEN="Waguri" \
    AGENT_MODE="true" \
    AGENT_MODE_VARIANT="modern" \
    STREAM_HOLDBACK="24" \
    LOG_LEVEL="info" \
    SYNC_MODE="false" \
    SESSION_POOL_SIZE="2" \
    UPSTREAM_MIN_INTERVAL_MS="200" \
    SESSION_ACQUIRE_TIMEOUT="10" \
    LOG_FORMAT="text"

# Playwright Go v0.6201.1 bundles Playwright 1.62.1. Install only Chromium
# and its Debian runtime dependencies. Node/npm are kept because this image is
# based on the official Node slim image and Playwright's Go driver may use them.
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends bash ca-certificates; \
    npx -y playwright@1.62.1 install --with-deps chromium; \
    rm -rf /root/.npm /root/.cache/node /var/lib/apt/lists/*

COPY --from=zai-builder /app/token-collector /app/token-collector
COPY --from=zai-builder /app/zai-api /app/zai-api
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

WORKDIR /app
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["./zai-api"]
