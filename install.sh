#!/bin/bash
set -euo pipefail

echo "=========================================================="
echo "⚡ AcexGateway - Native Linux (Systemd) Setup & Installer"
echo "=========================================================="

REPO="quaywin/acex"
INSTALL_ROOT="/opt/acex"
CONFIG_DIR="/etc/acex"
ENV_FILE="$CONFIG_DIR/env"
STORAGE_DIR="/var/lib/acex"
SERVICE_FILE="/etc/systemd/system/acex.service"
CLI_SCRIPT="/usr/local/bin/acex"

LOCAL_TARBALL=""
INTERACTIVE=false
if [ -t 0 ] || ([ -e /dev/tty ] && [ -r /dev/tty ] && [ -w /dev/tty ]); then
  INTERACTIVE=true
fi

while [ "$#" -gt 0 ]; do
  case "$1" in
    -y|--yes|--non-interactive)
      INTERACTIVE=false
      shift
      ;;
    --tarball)
      LOCAL_TARBALL="${2:-}"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done

if [ -n "${CI:-}" ] || [ "${DEBIAN_FRONTEND:-}" = "noninteractive" ]; then
  INTERACTIVE=false
fi

# 1. Require root
if [ "$EUID" -ne 0 ]; then
  echo "❌ Please run this installer as root (e.g. sudo bash install.sh)."
  exit 1
fi

# 2. Detect OS & Architecture (amd64 / arm64)
if [ "$(uname -s)" != "Linux" ]; then
  echo "❌ Native installer supports Linux (Debian, Ubuntu, Raspberry Pi OS 64-bit) only."
  exit 1
fi

if ! command -v apt-get >/dev/null 2>&1; then
  echo "❌ This native installer currently supports Debian/Ubuntu/Raspberry Pi OS (apt-get)."
  exit 1
fi

RAW_ARCH=$(uname -m)
case "$RAW_ARCH" in
  x86_64|amd64) ARCH="amd64" ;;
  aarch64|arm64) ARCH="arm64" ;;
  *)
    echo "❌ Unsupported architecture: $RAW_ARCH (requires 64-bit amd64 or arm64, e.g. Raspberry Pi OS 64-bit)."
    exit 1
    ;;
esac
echo "✓ Detected Linux ($ARCH)"

# 3. Install runtime dependencies
echo "ℹ Installing runtime dependencies..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y --no-install-recommends \
  libstdc++6 openssl libncurses6 ca-certificates curl tar procps ffmpeg >/dev/null

# 4. Prepare directories & storage
mkdir -p "$INSTALL_ROOT/releases" "$INSTALL_ROOT/bin" "$CONFIG_DIR" "$STORAGE_DIR"

# Migrate legacy data from current directory or Docker volume if present
for candidate in "./data" "$(pwd)/data" "/app/data" "$HOME/.acex/data"; do
  if [ -f "$candidate/channels.json" ] && [ ! -f "$STORAGE_DIR/channels.json" ]; then
    echo "ℹ Detected existing channels configuration at $candidate. Migrating to $STORAGE_DIR..."
    cp -a "$candidate/." "$STORAGE_DIR/" 2>/dev/null || true
    chmod -R 0755 "$STORAGE_DIR"
    echo "✓ Migrated channel and settings data to $STORAGE_DIR"
    break
  fi
done

ask_prompt() {
  local prompt="$1"
  local default_val="$2"
  local result=""

  if [ "$INTERACTIVE" = true ]; then
    if [ -t 0 ]; then
      read -r -p "$prompt" result || true
    elif [ -e /dev/tty ] && [ -r /dev/tty ] && [ -w /dev/tty ]; then
      printf "%s" "$prompt" > /dev/tty 2>/dev/null || true
      read -r result < /dev/tty 2>/dev/null || true
    fi
  fi

  if [ -z "$result" ]; then
    echo "$default_val"
  else
    echo "$result"
  fi
}

IS_UPGRADE=false
if [ -f "$ENV_FILE" ]; then
  IS_UPGRADE=true
  echo "✓ Existing configuration detected at $ENV_FILE (preserving settings)."
else
  DEFAULT_PORT="8686"
  DEFAULT_ACE_HOST="127.0.0.1"
  DEFAULT_ACE_PORT="6878"
  DEFAULT_ACE_TELNET="62062"

  echo ""
  echo "=== AcexGateway Configuration Setup ==="
  INPUT_PORT=$(ask_prompt "1. Acex Web Dashboard & Stream Port [$DEFAULT_PORT]: " "$DEFAULT_PORT")
  ACEX_PORT=$(echo "$INPUT_PORT" | tr -dc '0-9')
  [ -z "$ACEX_PORT" ] && ACEX_PORT="$DEFAULT_PORT"

  # AceStream Engine integration selection
  START_DOCKER_ENGINE=false
  if [ "$ARCH" = "amd64" ] && command -v docker >/dev/null 2>&1; then
    echo ""
    echo "ℹ Docker detected on x86_64 host."
    AUTO_DOCKER=$(ask_prompt "2. Do you want to automatically run AceStream Engine via Docker on 127.0.0.1? [Y/n]: " "Y")
    case "$AUTO_DOCKER" in
      [nN]|[nN][oO])
        START_DOCKER_ENGINE=false
        ;;
      *)
        START_DOCKER_ENGINE=true
        ;;
    esac
  fi

  if [ "$START_DOCKER_ENGINE" = true ]; then
    echo "ℹ Starting isolated AceStream Engine container..."
    if docker ps -a --format '{{.Names}}' | grep -Eq "^acex-acestream$"; then
      docker start acex-acestream >/dev/null 2>&1 || true
    else
      docker run -d \
        --name acex-acestream \
        --restart unless-stopped \
        -p 127.0.0.1:6878:6878 \
        -p 127.0.0.1:62062:62062 \
        -p 8621:8621/tcp \
        -p 8621:8621/udp \
        --tmpfs /root/.ACEStream/cache:size=512M,mode=1777 \
        --tmpfs /root/.ACEStream/buffer:size=256M,mode=1777 \
        smarquezp/docker-acestream-ubuntu-home:latest >/dev/null 2>&1 || true
    fi
    echo "✓ AceStream Engine running on 127.0.0.1 (HTTP: 6878, Telnet: 62062, P2P: 8621)"
    ACE_HOST="127.0.0.1"
  else
    if [ "$ARCH" = "arm64" ]; then
      echo ""
      echo "ℹ Note for Raspberry Pi / ARM64:"
      echo "  AceStream Engine runs on Android TV Box, Smart TV or remote x86 PC."
      INPUT_ACE_HOST=$(ask_prompt "2. AceStream Engine Host IP/Hostname [$DEFAULT_ACE_HOST]: " "$DEFAULT_ACE_HOST")
    else
      INPUT_ACE_HOST=$(ask_prompt "2. AceStream Engine Host IP/Hostname [$DEFAULT_ACE_HOST]: " "$DEFAULT_ACE_HOST")
    fi
    ACE_HOST=$(echo "$INPUT_ACE_HOST" | tr -d '[:space:]')
    [ -z "$ACE_HOST" ] && ACE_HOST="$DEFAULT_ACE_HOST"
  fi

  HOST_CORES=$(nproc 2>/dev/null || echo 1)
  TOTAL_RAM_MB=$(free -m 2>/dev/null | awk '/^Mem:/{print $2}' || echo 2048)
  AUTO_SWAP="false"
  DEFAULT_MAX_CHANNELS="5"

  if [ "$TOTAL_RAM_MB" -lt 1200 ]; then
    echo "ℹ Low-Memory environment detected (${TOTAL_RAM_MB}MB RAM). Enabling memory-saving profile."
    DEFAULT_MAX_CHANNELS="3"
    AUTO_SWAP="true"
  fi

  if [ "$HOST_CORES" -le 1 ]; then
    DEFAULT_ERL_AFLAGS="+S 1:1"
  else
    DEFAULT_ERL_AFLAGS="+S 2:2"
  fi

  cat <<EOF > "$ENV_FILE"
# AcexGateway Native Environment Configuration
MIX_ENV=prod
PORT=$ACEX_PORT
DATA_DIR=$STORAGE_DIR
CHANNELS_FILE=$STORAGE_DIR/channels.json
GROUPS_FILE=$STORAGE_DIR/groups.json
SETTINGS_FILE=$STORAGE_DIR/settings.json

# AceStream Engine Connection
ACE_TELNET_HOST=$ACE_HOST
ACE_TELNET_PORT=$DEFAULT_ACE_TELNET
ACE_HTTP_PORT=$DEFAULT_ACE_PORT
GRACE_PERIOD_MS=15000
MAX_ACTIVE_CHANNELS=$DEFAULT_MAX_CHANNELS

# Memory & scheduler tuning
ERL_AFLAGS=$DEFAULT_ERL_AFLAGS
ERL_CRASH_DUMP_SECONDS=0
ENABLE_SWAP=$AUTO_SWAP
EOF
  chmod 0600 "$ENV_FILE"
  echo "✓ Generated $ENV_FILE (Profile: ${DEFAULT_MAX_CHANNELS} max streams, swap: $AUTO_SWAP)"
fi

# 5. Download & extract release tarball atomically
RELEASE_ID=$(date +%Y%m%d%H%M%S)
RELEASE_DIR="$INSTALL_ROOT/releases/$RELEASE_ID"
mkdir -p "$RELEASE_DIR"

if [ -n "$LOCAL_TARBALL" ]; then
  echo "ℹ Extracting local release archive: $LOCAL_TARBALL"
  tar -xzf "$LOCAL_TARBALL" -C "$RELEASE_DIR"
else
  TARBALL_NAME="acex-linux-${ARCH}.tar.gz"
  TARBALL_URL="https://github.com/${REPO}/releases/latest/download/${TARBALL_NAME}"
  CHECKSUMS_URL="https://github.com/${REPO}/releases/latest/download/SHA256SUMS"
  echo "ℹ Downloading AcexGateway release ($ARCH) from $TARBALL_URL..."
  TMP_TAR=$(mktemp)
  TMP_SUMS=$(mktemp)
  if ! curl -fsSL "$TARBALL_URL" -o "$TMP_TAR"; then
    rm -f "$TMP_TAR" "$TMP_SUMS"
    rm -rf "$RELEASE_DIR"
    echo "❌ Failed to download $TARBALL_URL."
    echo "   Tip: Build a release tarball with:"
    echo "   MIX_ENV=prod mix release --overwrite && tar -czf ${TARBALL_NAME} -C _build/prod/rel/acex_gateway ."
    echo "   Then install using: sudo bash install.sh --tarball /path/to/${TARBALL_NAME}"
    exit 1
  fi
  if curl -fsSL "$CHECKSUMS_URL" -o "$TMP_SUMS"; then
    EXPECTED_SHA=$(grep -E "[[:space:]]${TARBALL_NAME}$" "$TMP_SUMS" | awk '{print $1}' | head -n1 || echo "")
    ACTUAL_SHA=$(sha256sum "$TMP_TAR" | awk '{print $1}')
    if [ -n "$EXPECTED_SHA" ]; then
      if [ "$EXPECTED_SHA" = "$ACTUAL_SHA" ]; then
        echo "✓ Verified SHA256 checksum"
      else
        rm -f "$TMP_TAR" "$TMP_SUMS"
        rm -rf "$RELEASE_DIR"
        echo "❌ SHA256 Checksum verification failed for ${TARBALL_NAME}!"
        echo "   Expected: $EXPECTED_SHA"
        echo "   Actual  : $ACTUAL_SHA"
        exit 1
      fi
    else
      echo "⚠ Warning: Checksum entry not found in SHA256SUMS for ${TARBALL_NAME}."
    fi
  else
    echo "⚠ Warning: Could not download SHA256SUMS; skipping checksum verification."
  fi
  tar --no-same-owner -xzf "$TMP_TAR" -C "$RELEASE_DIR"
  rm -f "$TMP_TAR" "$TMP_SUMS"
fi

chmod +x "$RELEASE_DIR/bin/server" "$RELEASE_DIR/bin/acex_gateway" 2>/dev/null || true
ln -sfn "$RELEASE_DIR" "$INSTALL_ROOT/current"

# Keep only the 2 most recent releases
CURRENT_TARGET=$(readlink -f "$INSTALL_ROOT/current" 2>/dev/null || echo "")
ls -1d "$INSTALL_ROOT/releases/"* 2>/dev/null | sort -r | tail -n +3 | while read -r old_rel; do
  [ -n "$old_rel" ] && [ "$old_rel" != "$CURRENT_TARGET" ] && rm -rf "$old_rel"
done

# 6. Install systemd service
cat <<'EOF' > "$SERVICE_FILE"
[Unit]
Description=AcexGateway Stream Hub & IPTV Gateway
Documentation=https://github.com/quaywin/acex
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/acex/current
Environment="PATH=/opt/acex/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
EnvironmentFile=/etc/acex/env
ExecStart=/opt/acex/current/bin/server
Restart=always
RestartSec=3
TimeoutStopSec=15
LimitNOFILE=65536
LockPersonality=true
RestrictRealtime=true
SystemCallArchitectures=native
StandardOutput=journal
StandardError=journal
SyslogIdentifier=acex

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable acex.service >/dev/null 2>&1
systemctl restart acex.service
echo "✓ Systemd service acex.service started"

# 7. Save installer locally for safe upgrades
if [ -f "$0" ] && [ "$(basename "$0")" != "bash" ] && [ "$(basename "$0")" != "sh" ]; then
  install -m 0755 "$0" "$INSTALL_ROOT/install.sh" 2>/dev/null || true
else
  curl -fsSL "https://raw.githubusercontent.com/${REPO}/main/install.sh" -o "$INSTALL_ROOT/install.sh" 2>/dev/null || true
  chmod 0755 "$INSTALL_ROOT/install.sh" 2>/dev/null || true
fi

# 8. Install CLI helper script
cat <<'EOF' > "$CLI_SCRIPT"
#!/bin/bash
set -euo pipefail

case "${1:-}" in
  status)
    systemctl status acex.service --no-pager
    ;;
  logs|log)
    shift
    journalctl -u acex.service -f "$@"
    ;;
  restart)
    sudo systemctl restart acex.service
    echo "✓ AcexGateway restarted."
    ;;
  start)
    sudo systemctl start acex.service
    echo "✓ AcexGateway started."
    ;;
  stop)
    sudo systemctl stop acex.service
    echo "✓ AcexGateway stopped."
    ;;
  update|upgrade)
    shift
    if [[ " $* " == *" --tarball "* ]] && [ -x /opt/acex/install.sh ]; then
      sudo /opt/acex/install.sh --yes "$@"
    else
      TMP_INSTALL=$(mktemp)
      if curl -fsSL "https://raw.githubusercontent.com/quaywin/acex/main/install.sh" -o "$TMP_INSTALL"; then
        sudo bash "$TMP_INSTALL" --yes "$@"
        rm -f "$TMP_INSTALL"
      elif [ -x /opt/acex/install.sh ]; then
        rm -f "$TMP_INSTALL"
        echo "⚠ Could not fetch latest installer from GitHub; falling back to /opt/acex/install.sh."
        sudo /opt/acex/install.sh --yes "$@"
      else
        rm -f "$TMP_INSTALL"
        echo "❌ Failed to download latest installer."
        exit 1
      fi
    fi
    ;;
  env|info)
    sudo cat /etc/acex/env
    ;;
  engine)
    source /etc/acex/env 2>/dev/null || true
    HOST="${ACE_TELNET_HOST:-127.0.0.1}"
    TELNET_PORT="${ACE_TELNET_PORT:-62062}"
    HTTP_PORT="${ACE_HTTP_PORT:-6878}"

    echo "=== AceStream Engine Connectivity Check ==="
    echo "Target: $HOST (Telnet API: $TELNET_PORT, HTTP API: $HTTP_PORT)"

    TELNET_OK=false
    if command -v nc >/dev/null 2>&1; then
      nc -z -w 2 "$HOST" "$TELNET_PORT" >/dev/null 2>&1 && TELNET_OK=true || true
    elif (echo > /dev/tcp/"$HOST"/"$TELNET_PORT") 2>/dev/null; then
      TELNET_OK=true
    fi

    HTTP_OK=false
    if command -v curl >/dev/null 2>&1; then
      HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -m 2 "http://$HOST:$HTTP_PORT/app/test" 2>/dev/null || echo "")
      if [ -n "$HTTP_CODE" ] && [ "$HTTP_CODE" != "000" ]; then
        HTTP_OK=true
      fi
    elif (echo > /dev/tcp/"$HOST"/"$HTTP_PORT") 2>/dev/null; then
      HTTP_OK=true
    fi

    if [ "$TELNET_OK" = true ]; then
      echo "  • Telnet API (port $TELNET_PORT) : ✓ REACHABLE"
    else
      echo "  • Telnet API (port $TELNET_PORT) : ❌ UNREACHABLE"
    fi

    if [ "$HTTP_OK" = true ]; then
      echo "  • HTTP API   (port $HTTP_PORT)  : ✓ REACHABLE"
    else
      echo "  • HTTP API   (port $HTTP_PORT)  : ❌ UNREACHABLE"
    fi
    ;;
  *)
    echo "Usage: acex {status|logs|restart|start|stop|update|env|engine}"
    exit 1
    ;;
esac
EOF
chmod +x "$CLI_SCRIPT"

SERVER_IP=$(hostname -I 2>/dev/null | awk '{print $1}' || ip route get 1.1.1.1 2>/dev/null | awk '{print $7}' || echo "localhost")
[ -z "$SERVER_IP" ] && SERVER_IP="localhost"

echo ""
echo "=========================================================="
echo "🎉 AcexGateway Native Setup Completed Successfully!"
echo "=========================================================="
echo "• Dashboard URL : http://${SERVER_IP}:${ACEX_PORT:-8686}"
echo "• Service Name  : acex.service"
echo "• Data Storage  : $STORAGE_DIR"
echo "• CLI Helper    : acex status | acex logs | acex restart | acex update | acex engine"
echo "=========================================================="
