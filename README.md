<p align="center">
  <a href="https://github.com/quaywin/acex">
    <img src="assets/logo.svg" alt="Acex Logo" width="96" height="96">
  </a>
</p>

<h1 align="center">Acex</h1>

<p align="center">
  <strong>High-Performance 0-Transcode Stream Gateway & IPTV Hub for AceStream</strong>
</p>

<p align="center">
  <a href="https://github.com/quaywin/acex/releases"><img src="https://img.shields.io/github/v/release/quaywin/acex?style=flat&color=E11D48" alt="Latest Release"></a>
  <a href="https://github.com/quaywin/acex/pkgs/container/acex"><img src="https://img.shields.io/badge/Docker-ghcr.io%2Fquaywin%2Facex-blue?logo=docker" alt="Docker Container"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-success.svg" alt="MIT License"></a>
  <img src="https://img.shields.io/badge/Port-8686-orange.svg" alt="Port 8686">
</p>

---

Acex is an enterprise-grade, ultra-lightweight **Stream Gateway & IPTV Relay** for AceStream. It replaces legacy proxies with a concurrent, fault-tolerant relay hub designed specifically for **Docker, Homelab, NAS, and VPS** setups—delivering instantaneous, stutter-free playback to Smart TVs and media players.

```
[ P2P Swarms ] ──▶ [ AceStream Engine ] ──▶ [ AcexGateway ] ──┬──▶ Living Room TV (Channel A)
                       (20s Live Buffer)     (4MB RingBuffers) ├──▶ Bedroom TV (Channel B)
                                             (Multi-Channel    └──▶ Mobile / VLC (Shared A)
                                              + Failover)
```

---

## ✨ Key Features

- **⚡ Zero-Transcode & Fast-Start Engine**: Relays pristine MPEG-TS streams directly with zero CPU transcoding. An in-memory 4MB RingBuffer delivers PAT/PMT headers and video keyframes instantly upon tuning.
- **🔀 Multi-Channel Concurrency & Smart Fan-Out**: Stream different channels across multiple rooms and devices simultaneously. When multiple clients tune into the same channel, Acex shares a single upstream P2P connection (1-to-many relay), conserving bandwidth.
- **🛡️ Multi-Source Auto-Failover**: Configure multiple backup Content IDs per channel. If the primary stream drops peers or stalls, Acex seamlessly fails over to backup sources in the background.
- **📺 Universal IPTV Hub (Xtream Codes & M3U8)**: Native support for **TiviMate**, **IPTV Smarters**, and **XCIPTV** via `/player_api.php`, alongside extended M3U8 playlists with categories, channel logos, and XMLTV EPG.
- **🎛️ StreamFlix NOC Dashboard**: Sleek web console with real-time P2P swarm telemetry, lineup manager with bulk M3U import, QR code connect, and 1-click launch for **VLC**, **IINA**, and **PotPlayer**.

---

## 🚀 Quick Start with Docker

The easiest way to run Acex is using the pre-built all-in-one container from GitHub Container Registry:

### `docker-compose.yml`

```yaml
services:
  acex:
    image: ghcr.io/quaywin/acex:latest
    container_name: acex-gateway
    restart: unless-stopped
    ports:
      - "8686:8686"       # Web Dashboard & Stream Relay
      - "6878:6878"       # AceStream HTTP API
      - "62062:62062"     # AceStream Telnet API
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
Access the Dashboard at **[http://localhost:8686](http://localhost:8686)**.

> **💡 Host Network Tip:** On a dedicated Linux host or VPS, use `network_mode: host` instead of `ports:` to bypass Docker NAT and maximize P2P swarm peer discovery.

---

## 📱 Connect Your Devices

### 1. Smart TV (TiviMate / IPTV Smarters / XCIPTV)

* **Via Xtream Codes API (Recommended):**
  - **Server URL:** `http://<SERVER_IP>:8686`
  - **Username / Password:** Your configured credentials (or leave blank if disabled)
* **Via M3U8 Playlist:**
  - Enter URL: `http://<SERVER_IP>:8686/playlist.m3u8`
  - Or scan the on-screen QR code from the Web Dashboard.

### 2. Desktop & Mobile Players (VLC, IINA, PotPlayer)

* Click any channel in the Web Dashboard and hit **VLC**, **IINA**, or **PotPlayer** for 1-click launch.
* Or open Network Stream in VLC:
  ```text
  http://<SERVER_IP>:8686/playlist.m3u8
  ```

---

## 🔌 API Endpoints

| Endpoint | Type | Description |
| :--- | :--- | :--- |
| `GET /` | Web UI | StreamFlix Management Dashboard |
| `GET /player_api.php` | Xtream API | Xtream Codes API handshake, categories, and streams |
| `GET /playlist.m3u8` | M3U8 | Standard IPTV playlist for TV players |
| `GET /live/:target.ts` | MPEG-TS | Live video stream by slug or 40-char Content ID |
| `GET /stat` | JSON | Real-time swarm peers, bitrate, and viewer telemetry |
| `GET /api/channels` | REST | List channels (supports POST/PUT/DELETE) |
| `GET /api/channels/export` | File | Export lineup as `.txt`, `.m3u8`, or `.json` |
| `GET /health` | Healthcheck | Docker / Kubernetes readiness probe |

---

## ⚙️ Configuration Reference

| Environment Variable | Default | Description |
| :--- | :--- | :--- |
| `PORT` | `8686` | Web Dashboard and stream relay port |
| `ACE_LIVE_BUFFER` | `20` | P2P live buffer in seconds (sweet spot for sports) |
| `ACE_MAX_PEERS` | `80` | Maximum P2P peers connected per stream |
| `RING_BUFFER_BYTES` | `4194304` | Gateway in-memory buffer (4MB ~ 5-6s of 1080p stream) |
| `GRACE_PERIOD_MS` | `15000` | Warm swarm retention delay (ms) after last viewer exits |
| `AUTH_USERNAME` | *(empty)* | Optional authentication username |
| `AUTH_PASSWORD` | *(empty)* | Optional authentication password |
| `EPG_URL` | *(empty)* | Custom XMLTV EPG URL |
| `CHANNELS_FILE` | `/app/data/channels.json` | Persistent channel directory |

---

## 🛠️ Development & Building from Source

```bash
# Clone the repository
git clone https://github.com/quaywin/acex.git
cd acex

# Install dependencies & run tests
mix deps.get
mix test

# Run locally
mix run --no-halt
```

---

## 📄 License

This project is licensed under the [MIT License](LICENSE).
