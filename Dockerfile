# ============================================================
# Stage 1: Build Elixir OTP Release (Ubuntu Jammy 22.04 AMD64)
# ============================================================
FROM --platform=linux/amd64 hexpm/elixir:1.18.3-erlang-27.3-ubuntu-jammy-20250126 AS builder

RUN apt-get update && \
    apt-get install -y --no-install-recommends git build-essential && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

ENV MIX_ENV=prod \
    ERL_FLAGS="+JMsingle true"

# Install Hex & Rebar
RUN mix local.hex --force && \
    mix local.rebar --force

# Cache dependencies
COPY mix.exs mix.lock ./
RUN mix deps.get --only prod
RUN mix deps.compile

# Compile & build release
COPY config config
COPY lib lib
RUN mix compile
RUN mix release

# ============================================================
# Stage 2: All-in-One Runner (AceStream Engine + AcexGateway)
# ============================================================
FROM --platform=linux/amd64 smarquezp/docker-acestream-ubuntu-home:latest AS runner

RUN apt-get update && \
    apt-get install -y --no-install-recommends curl ca-certificates && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy Elixir OTP release from builder
COPY --from=builder /app/_build/prod/rel/acex_gateway /app/

# Copy All-in-One entrypoint
COPY docker-entrypoint.sh /docker-entrypoint.sh
RUN chmod +x /docker-entrypoint.sh && mkdir -p /app/data

EXPOSE 8686 6878 62062 8621/tcp 8621/udp

ENV PORT=8686 \
    HTTP_PORT=6878 \
    HTTPS_PORT=6879 \
    ACE_TELNET_HOST=127.0.0.1 \
    ACE_TELNET_PORT=62062 \
    ACE_HTTP_PORT=6878 \
    GRACE_PERIOD_MS=5000 \
    CHANNELS_FILE=/app/data/channels.json \
    ERL_FLAGS="+JMsingle true"

HEALTHCHECK --interval=15s --timeout=5s --retries=3 \
    CMD curl -f http://127.0.0.1:8686/health || exit 1

ENTRYPOINT ["/usr/bin/tini", "-g", "--", "/docker-entrypoint.sh"]
