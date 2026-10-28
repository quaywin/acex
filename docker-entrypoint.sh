#!/bin/bash
set -e

echo "=========================================================="
echo "⚡ AcexGateway All-in-One (AceStream Engine + Elixir OTP)"
echo "=========================================================="

HTTP_PORT="${HTTP_PORT:-6878}"
HTTPS_PORT="${HTTPS_PORT:-6879}"
ACE_LIVE_BUFFER="${ACE_LIVE_BUFFER:-20}"
ACE_MAX_PEERS="${ACE_MAX_PEERS:-15}"
ACE_MEMORY_CACHE_LIMIT="${ACE_MEMORY_CACHE_LIMIT:-268435456}"
ACESTREAM_EXTRA_FLAGS="${ACESTREAM_EXTRA_FLAGS:---live-cache-type memory --memory-cache-limit ${ACE_MEMORY_CACHE_LIMIT} --live-buffer ${ACE_LIVE_BUFFER} --max-peers ${ACE_MAX_PEERS}}"

# Ensure data and cache directories exist
mkdir -p /app/data /root/.ACEStream/cache /root/.ACEStream/buffer /root/.ACEStream/content_cache /tmp /dev/disk/by-id 2>/dev/null || true

# 1. Start AceStream Engine Daemon
echo "[All-in-One] Starting AceStream Engine on ports ${HTTP_PORT} (HTTP) / 62062 (Telnet)..."
/opt/acestream/start-engine \
    --http-port "${HTTP_PORT}" \
    --https-port "${HTTPS_PORT}" \
    ${ACESTREAM_EXTRA_FLAGS} \
    "@/opt/acestream/acestream.conf" &
ACE_PID=$!

# Signal handler for graceful shutdown
cleanup() {
    echo ""
    echo "[All-in-One] Received termination signal. Shutting down gracefully..."
    if [ -n "$ACEX_PID" ]; then
        kill -TERM "$ACEX_PID" 2>/dev/null || true
    fi
    if [ -n "$ACE_PID" ]; then
        kill -TERM "$ACE_PID" 2>/dev/null || true
    fi
    wait "$ACEX_PID" 2>/dev/null || true
    wait "$ACE_PID" 2>/dev/null || true
    echo "[All-in-One] All services stopped."
    exit 0
}

trap cleanup SIGTERM SIGINT SIGQUIT

# 2. Wait up to 15 seconds for AceStream Telnet API to be ready
echo "[All-in-One] Waiting for AceStream Engine Telnet API on 127.0.0.1:62062..."
for i in {1..30}; do
    if (echo > /dev/tcp/127.0.0.1/62062) 2>/dev/null; then
        echo "[All-in-One] AceStream Engine is ready (connected in ${i}x0.5s)!"
        break
    fi
    sleep 0.5
done

# 3. Start AcexGateway OTP Release in background and wait
echo "[All-in-One] Starting AcexGateway Web & Stream Relay on port ${PORT:-8686}..."
/app/bin/acex_gateway start &
ACEX_PID=$!

# Wait for either process to exit
wait -n "$ACEX_PID" "$ACE_PID"
cleanup
