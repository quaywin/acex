<p align="center">
  <a href="https://github.com/quaywin/acex">
    <img src="assets/logo.svg" alt="Acex Logo" width="96" height="96">
  </a>
</p>

<h1 align="center">Acex</h1>

<p align="center">
  <strong>0-Transcode Stream Gateway and IPTV Hub for AceStream</strong>
</p>

<p align="center">
  <a href="https://github.com/quaywin/acex/releases"><img src="https://img.shields.io/github/v/release/quaywin/acex?style=flat&color=E11D48" alt="Latest Release"></a>
  <a href="https://github.com/quaywin/acex/pkgs/container/acex"><img src="https://img.shields.io/badge/Docker-ghcr.io%2Fquaywin%2Facex-blue?logo=docker" alt="Docker Container"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-success.svg" alt="MIT License"></a>
  <img src="https://img.shields.io/badge/Port-8686-orange.svg" alt="Port 8686">
</p>

---

Acex is a lightweight stream gateway and IPTV relay for AceStream. It converts AceStream P2P swarms into standard HTTP MPEG-TS feeds for Smart TVs, IPTV apps, and media players.

```
[ P2P Swarms ] ──▶ [ AceStream Engine ] ──▶ [ AcexGateway ] ──┬──▶ Living Room TV (Channel A)
                       (20s Live Buffer)     (4MB RingBuffers) ├──▶ Bedroom TV (Channel B)
                                             (Multi-Channel    └──▶ Mobile / VLC (Shared A)
                                              + Failover)
```

---

## Features

- **Zero-Transcode Passthrough**: Relays MPEG-TS packets directly without CPU transcoding. An in-memory ring buffer delivers keyframes immediately on channel switch.
- **Multi-Channel and Fan-Out Relay**: Streams multiple channels concurrently. Multiple clients watching the same channel share a single upstream connection to save bandwidth.
- **Multi-Source Failover & Smart Auto-Promotion**: Supports fallback Content IDs per channel with sub-second failover on dead sources (`STATE 6`, `STATUS main:error`, fatal `LOADRESP`), zero-peer fast switching, transparent mid-stream recovery without dropping connected player sessions, and automatic promotion of healthy backup sources to primary.
- **Content ID Pre-Validation & Dead Source Pruning**: Pre-checks torrent swarm availability (`LOADASYNC`) directly in the channel editor without video buffering or credit cost (memoized in ETS). Automatically prunes fatal dead hashes during playback while preserving channel integrity (never deletes the final remaining source), with 1-click fleet-wide cleanup (`POST /api/channels/prune-all-dead`).
- **Xtream Codes API and M3U8**: Compatible with TiviMate, IPTV Smarters, and XCIPTV via `/player_api.php`, plus standard M3U8 playlists with EPG support.
- **In-Dashboard Web Video Player & Chromecast**: Instant in-browser MPEG-TS live playback using HTML5 MSE decoding (`mpegts.js`), plus 1-click casting to Chromecast & Google TV devices via on-demand, zero-video-transcode HLS remuxing with AAC audio compatibility.
- **In-Dashboard 1-Click System Updater**: Automated GitHub Releases checker with ETS caching, changelog inspector, and 1-click update trigger via internal Watchtower HTTP API with automatic polling and page reload, plus 1-line CLI script `./update.sh`.
- **Web Dashboard & Live Telemetry**: Manage channels, inspect Fleet Health metrics (total, multi-source, single-source, active streams), smart filter chips, one-click clipboard hash extractor, priority fallback reordering (`▲/▼`), real-time prebuffering progress (`%`), and stream launchers for VLC, IINA, or PotPlayer.

---

## Quick Start

### 1. Docker Run (Fastest)

```bash
docker run -d \
  --name acex-gateway \
  --restart unless-stopped \
  -p 8686:8686 \
  -p 8621:8621/tcp \
  -p 8621:8621/udp \
  -v $(pwd)/data:/app/data \
  --tmpfs /root/.ACEStream/cache:size=512M,mode=1777 \
  --tmpfs /root/.ACEStream/buffer:size=256M,mode=1777 \
  --tmpfs /tmp:size=128M,mode=1777 \
  -e ACE_LIVE_BUFFER=20 \
  -e ACE_MAX_PEERS=15 \
  -e ACE_MAX_UPLOAD_RATE=500 \
  -e ACE_MEMORY_CACHE_LIMIT=268435456 \
  ghcr.io/quaywin/acex:latest
```

### 2. Docker Compose

`docker-compose.yml`:

```yaml
services:
  acex-gateway:
    image: ghcr.io/quaywin/acex:latest
    container_name: acex-gateway
    restart: unless-stopped
    ports:
      - "8686:8686"       # Web Dashboard, IPTV API & Stream Relay
      - "8621:8621/tcp"   # P2P Incoming Swarm
      - "8621:8621/udp"
    volumes:
      - ./data:/app/data
    tmpfs:
      - /root/.ACEStream/cache:size=512M,mode=1777
      - /root/.ACEStream/buffer:size=256M,mode=1777
    environment:
      - PORT=8686
      - ACE_LIVE_BUFFER=20
      - ACE_MAX_PEERS=15
      - ACE_MAX_UPLOAD_RATE=500
      - ACE_MEMORY_CACHE_LIMIT=268435456
      - GRACE_PERIOD_MS=15000
      - WATCHTOWER_ENDPOINT=http://acex-watchtower:8080/v1/update
      - WATCHTOWER_HTTP_API_TOKEN=acex_update_token

  # Automated 1-Click Container Updater (Internal HTTP API)
  acex-watchtower:
    image: containrrr/watchtower:latest
    container_name: acex-watchtower
    restart: unless-stopped
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
    environment:
      - DOCKER_API_VERSION=1.44
      - WATCHTOWER_HTTP_API_UPDATE=true
      - WATCHTOWER_HTTP_API_TOKEN=acex_update_token
      - WATCHTOWER_CLEANUP=true
      - WATCHTOWER_POLL_INTERVAL=86400
```

```bash
docker compose up -d
```

Open the dashboard at **http://localhost:8686**.

> **Tip:** On a dedicated Linux host or VPS, use `--network host` (or `network_mode: host` in compose) to eliminate Docker NAT overhead and maximize P2P swarm discovery.

---

## Updating AcexGateway

### 1. In-Dashboard 1-Click Update (Easiest)
1. Open the Web Dashboard at `http://<SERVER_IP>:8686`.
2. Look at the top navigation bar badge:
   - `v0.6.4 ✓`: Your system is up-to-date.
   - `🚀 New version: vX.Y.Z`: A newer release is available.
3. Click the badge to open the **System Update Modal**:
   - Inspect the release notes / changelog.
   - Click **"⚡ Update Now (1-Click)"**. AcexGateway invokes Watchtower over Docker's internal network to pull the new image, recreate the container, and automatically refresh the dashboard when back online.

### 2. One-Line CLI Script
Run the automated update script from the project root:
```bash
./update.sh
```

### 3. Manual Docker Compose
```bash
docker compose pull && docker compose up -d
```

---

## Connect Devices

### Smart TV (TiviMate / IPTV Smarters / XCIPTV)

* **Xtream Codes API (Recommended):**
  - **Server URL:** `http://<SERVER_IP>:8686`
  - **Username / Password:** Configured credentials (leave empty if auth is disabled)
* **M3U8 Playlist:**
  - URL: `http://<SERVER_IP>:8686/playlist.m3u8`
  - Or scan the QR code from the Web Dashboard.

### Desktop and Mobile Players (VLC, IINA, PotPlayer)

* Click any channel in the Web Dashboard to launch directly in VLC, IINA, or PotPlayer.
* Or open network stream:
  ```text
  http://<SERVER_IP>:8686/playlist.m3u8
  ```

---

## Endpoints

| Endpoint | Protocol / Format | Recommended For |
| :--- | :--- | :--- |
| `GET /player_api.php` | Xtream Codes API | TiviMate, IPTV Smarters, XCIPTV |
| `GET /playlist.m3u8` | Extended M3U Playlist | Apple TV, Smart TV, OTT Navigator |
| `GET /live/:target.ts` | Direct MPEG-TS Stream | VLC, IINA, PotPlayer, MPV |
| `GET /` | Web Console | Channel management and player launcher |
| `POST /api/channels/validate-source` | JSON API | Content ID health check (no buffering, ETS memoized) |
| `POST /api/channels/:id/prune-dead` | JSON API | One-click dead source pruning (keeps $\ge 1$ source) |
| `POST /api/channels/prune-all-dead` | JSON API | Bulk prune dead sources across multi-source channels (keeps $\ge 1$ source) |
| `GET /api/system/version` | JSON API | Check current vs latest GitHub release with changelog |
| `POST /api/system/update` | JSON API | 1-Click trigger for Watchtower / background update |

---

## Configuration

| Environment Variable | Default | Description |
| :--- | :--- | :--- |
| `PORT` | `8686` | Web Dashboard and stream relay port |
| `ACE_LIVE_BUFFER` | `20` | P2P live buffer in seconds |
| `ACE_MAX_PEERS` | `15` | Maximum P2P peers connected per stream |
| `ACE_MAX_UPLOAD_RATE` | `500` | Maximum P2P upload speed limit in KB/s (prevents uplink saturation) |
| `ACE_MEMORY_CACHE_LIMIT` | `268435456` | Maximum AceStream memory cache in bytes (256MB) |
| `RING_BUFFER_BYTES` | `4194304` | In-memory buffer size in bytes (4MB) |
| `GRACE_PERIOD_MS` | `15000` | Keep-alive delay in ms after last viewer leaves |
| `AUTH_USERNAME` | *(empty)* | Optional authentication username |
| `AUTH_PASSWORD` | *(empty)* | Optional authentication password |
| `EPG_URL` | *(empty)* | Custom XMLTV EPG URL |
| `CHANNELS_FILE` | `/app/data/channels.json` | Path to persistent channel storage |

---

## Development

```bash
# Clone the repository
git clone https://github.com/quaywin/acex.git
cd acex

# Install dependencies and run tests
mix deps.get
mix test

# Run locally
mix run --no-halt
```

---

## License

This project is licensed under the [MIT License](LICENSE).
