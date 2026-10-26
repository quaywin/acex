# Acex ⚡

[![Elixir: 1.18](https://img.shields.io/badge/Elixir-1.18%2B-purple.svg)](https://elixir-lang.org)
[![Erlang/OTP: 27](https://img.shields.io/badge/Erlang%2FOTP-27-red.svg)](https://www.erlang.org)
[![HTTP Server: Bandit](https://img.shields.io/badge/HTTP%20Server-Bandit%201.6-blue.svg)](https://github.com/mtrudel/bandit)
[![Stream Port: 8686](https://img.shields.io/badge/Stream%20Port-8686-orange.svg)]()
[![Docker: Ready](https://img.shields.io/badge/Docker-All--in--One%20Container-success.svg)]()
[![License: MIT](https://img.shields.io/badge/License-MIT-brightgreen.svg)](LICENSE)

An ultra-lightweight, high-performance **Headless LAN Stream Gateway & IPTV Relay** for AceStream, built entirely on **Elixir / OTP** and the **Bandit** HTTP server.

Acex delivers an enterprise-grade upgrade and full replacement for legacy Python gateways (`acehub_proxy.py`) across **Docker, Homelab, NAS, and VPS** environments—bringing instantaneous, artifact-free, and fault-tolerant live TV playback to Smart TVs and media players worldwide.

---

## 🌟 Key Features & Architectural Highlights

1. **📺 Auto-Generated M3U Playlist (`/playlist.m3u`)**:
   - Automatically exports standard IPTV playlists (`#EXTM3U`) complete with high-resolution channel logos and dynamic category grouping (Sports, News, Entertainment, etc.).
   - Smart Host Detection: Operates seamlessly across local **LAN**, **Tailscale** private mesh networks (`http://100.x.x.x:8686/playlist.m3u`), or **Custom Domains**.
   - One-click import into **TiviMate, IPTV Smarters, OTT Navigator, Apple TV, VLC**, enabling instant channel surfing like traditional cable television.

2. **⚡ Multi-Format Live Streaming (`/live`)**:
   - `http://<IP>:8686/live?id=<CONTENT_ID>`: Direct playback via Content ID (PID).
   - `http://<IP>:8686/live?channel=<SLUG>`: Channel lineup playback with active **Auto-Failover** protection.
   - Supports both chunked streaming **`GET`** and header probing **`HEAD`** requests for picky media players.

3. **🧹 Auto-Sanitize Stream Hashes**:
   - Automatically scrubs URL noise, `acestream://` schemes, `&pid=...` query parameters, and extraneous whitespace copied from the web, returning a canonical 40-character hex string to the engine.

4. **🛡️ Dynamic Auto-Failover**:
   - Channels support multiple backup broadcast sources (`sources: ["primary_hash", "backup_hash_1", "backup_hash_2"]`).
   - If the active stream encounters network drops or hits 0 peers, the gateway automatically switches to the next available backup source in the background without interrupting client playback.

5. **🚀 MPEG-TS Keyframe RingBuffer (Instant Playback & Anti-Artifact)**:
   - Maintains a rolling ~2MB memory buffer of recent video chunks in BEAM process memory.
   - When a player connects to an active stream, the RingBuffer immediately delivers PAT/PMT packets and the latest keyframe, **eliminating 3–5s black screens and initial pixelation**.

6. **⚡ Non-Blocking Asynchronous Architecture**:
   - Stream startup and P2P swarm pre-buffering are non-blocking (`status: "starting"`).
   - The Web Dashboard and `/stat` telemetry API **never freeze or time out**.

7. **👥 Multi-Channel Concurrent Streaming & Zero-Copy Fan-Out**:
   - **True Multi-Channel Concurrency**: Watch different channels simultaneously on different TVs, mobile phones, or desktop players. Starting, switching, or stopping a channel on one device never interrupts streams on other devices.
   - **Dynamic OTP Supervision**: Supervised on-demand by `DynamicSupervisor` and `Registry`. Channels automatically spawn dedicated `ChannelBroadcaster` processes with isolated AceStream engine sessions, and gracefully shut down with auto-cooldown when viewer counts reach zero.
   - **Shared Channel Zero-Copy Fan-Out**: Multiple devices watching the same channel share one `ChannelBroadcaster` instance and RingBuffer via BEAM **Refc Binaries**, saving memory and local network bandwidth. Slow connections on one screen never drag down or stutter other screens (no head-of-line blocking).

8. **🎛️ StreamFlix Mission Control Dashboard (`/`)**:
   - Dark cinematic NOC interface with crimson accents (`#E11D48`), glowing vector badge, and SVG favicon.
   - **⚡ Quick Stream Launcher**: Paste any Content ID or `acestream://` link for instant preview or direct streaming without adding it to the channel directory.
   - **📱 Smart TV QR Code Generator**: Generates an on-screen QR code for mobile devices or Smart TV cameras to scan the M3U playlist URL directly without typing.
   - **🎬 1-Click App Deep Links**: Launch streams directly into dedicated native video players (**VLC**, **IINA**, **PotPlayer**) or open in a browser tab.
   - **📂 Dynamic Filtering & Multi-View**: Switch effortlessly between visual media **Grid View** and compact administration **Table View**.

---

## 🔌 API & Endpoint Reference

| Endpoint | Protocol | Description |
| :--- | :--- | :--- |
| `GET /playlist.m3u` | M3U8 Playlist | Dynamic IPTV playlist for TiviMate, OTT Navigator, VLC |
| `GET /live?id=<ID>` | HTTP Chunked | Stream by Content ID (`video/mp2t`) |
| `GET /live?channel=<SLUG>` | HTTP Chunked | Stream by channel slug with Auto-Failover |
| `HEAD /live?...` | HTTP Header | Probe stream Content-Type for picky players |
| `GET /stat` | JSON | Telemetry: Bitrate, swarm peers, active clients, buffer status |
| `GET /api/channels` | JSON | Fetch all configured channels |
| `POST /api/channels` | JSON | Create or update a channel |
| `PUT /api/channels/:id` | JSON | Update channel by ID |
| `DELETE /api/channels/:id` | JSON | Remove channel from directory |
| `OPTIONS /...` | HTTP Header | CORS preflight for web clients |
| `GET /restart` | JSON | Reset all channels or a specific channel (`?channel=<SLUG>`) |
| `GET /health` | Plaintext | Healthcheck (`OK`) for Docker / Kubernetes |
| `GET /favicon.ico` | SVG Vector | Crisp vector brand favicon |
| `GET /` | HTML | StreamFlix Mission Control Web Dashboard |

---

## 📱 Device Setup Guide

### 1. TiviMate / IPTV Smarters / OTT Navigator (Android TV / Fire TV)
1. Open **TiviMate** $\to$ **Add Playlist** $\to$ Select **M3U Playlist**.
2. Enter the URL:
   ```text
   http://<SERVER_IP>:8686/playlist.m3u
   ```
   *(Example via LAN: `http://192.168.1.100:8686/playlist.m3u` or via Tailscale: `http://100.81.62.112:8686/playlist.m3u`)*.
3. Select **Done**. Your complete channel lineup with logos and categories is ready for remote-control channel surfing.

### 2. VLC Media Player (PC, Mac, iOS, Android)
* **Option 1 (Full Playlist):** Go to `Media` $\to$ `Open Network Stream...` $\to$ Paste:
  ```text
  http://<SERVER_IP>:8686/playlist.m3u
  ```
* **Option 2 (Direct Single Stream):**
  ```text
  http://<SERVER_IP>:8686/live?id=eab7aeef0218ce8b0752e596e4792b69eda4df5e
  ```

---

## ⚙️ Configuration & Environment Variables

| Variable | Default | Purpose |
| :--- | :--- | :--- |
| `PORT` or `ACE_PROXY_PORT` | `8686` | HTTP Gateway port for video streaming and Web Dashboard |
| `ACE_TELNET_HOST` | `127.0.0.1` | AceStream Engine Telnet API host address |
| `ACE_TELNET_PORT` | `62062` | AceStream Engine Telnet API port |
| `ACE_HTTP_PORT` | `6878` | AceStream Engine HTTP streaming port |
| `GRACE_PERIOD_MS` | `5000` | Cooldown delay (ms) after clients disconnect before stopping the engine |
| `CHANNELS_FILE` | `data/channels.json` | Persistent storage path for channel configurations |
| `DEFAULT_CHANNEL_ID` | `dd8255...` | Default Content ID fallback |

---

## 🚀 Deployment

### Option 1: All-in-One Docker Container (Recommended)

Acex integrates both **AceStream Engine Daemon + AcexGateway Elixir/OTP Relay** into a **single, unified Docker container** (compatible with both x86_64 and Apple Silicon M1/M2/M3/M4):

```bash
# Clone the repository
git clone git@github.com:quaywin/acex.git
cd acex

# Launch the unified All-in-One container
docker compose up -d

# Inspect live logs for both Engine and Gateway
docker compose logs -f acex-gateway
```

Or run directly using standard `docker run`:
```bash
docker run -d \
  --name acex-gateway \
  -p 8686:8686 \
  -p 6878:6878 \
  -p 62062:62062 \
  -p 8621:8621/tcp \
  -p 8621:8621/udp \
  -v ./data:/app/data \
  acex_gateway-acex-gateway
```

### Option 2: Local Development

Requires **Elixir >= 1.18** and **Erlang/OTP >= 27**.

```bash
cd acex

# Install dependencies
mix deps.get

# Run automated test suite
mix test

# Start the server
mix run --no-halt
```

Once running, access the Web Dashboard at: **[http://localhost:8686/](http://localhost:8686/)**

---

## 📄 License
This project is open-source software licensed under the [MIT License](LICENSE).
