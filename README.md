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
- **Multi-Source Failover**: Supports fallback Content IDs per channel, automatically switching sources if the primary stream stalls or loses peers.
- **Xtream Codes API and M3U8**: Compatible with TiviMate, IPTV Smarters, and XCIPTV via `/player_api.php`, plus standard M3U8 playlists with EPG support.
- **Web Dashboard**: Manage channels, view real-time swarm telemetry, import playlists, and launch streams directly in VLC, IINA, or PotPlayer.

---

## Quick Start

Run using Docker Compose:

### `docker-compose.yml`

```yaml
services:
  acex:
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
      - /root/.ACEStream/cache:size=1024M,mode=1777
      - /root/.ACEStream/buffer:size=512M,mode=1777
    environment:
      - PORT=8686
      - ACE_LIVE_BUFFER=20
      - ACE_MAX_PEERS=80
      - GRACE_PERIOD_MS=15000
```

Start the container:
```bash
docker compose up -d
```
Open the dashboard at **http://localhost:8686**.

> **Tip:** On a dedicated Linux host or VPS, use `network_mode: host` instead of `ports:` to eliminate Docker NAT overhead and maximize P2P swarm discovery.

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

---

## Configuration

| Environment Variable | Default | Description |
| :--- | :--- | :--- |
| `PORT` | `8686` | Web Dashboard and stream relay port |
| `ACE_LIVE_BUFFER` | `20` | P2P live buffer in seconds |
| `ACE_MAX_PEERS` | `80` | Maximum P2P peers connected per stream |
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
