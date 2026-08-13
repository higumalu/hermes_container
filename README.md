# Hermes Agent GUI Container

**English** | [中文說明](README.zh-TW.md)

A Docker setup that extends the official [nousresearch/hermes-agent](https://hub.docker.com/r/nousresearch/hermes-agent) image with a Linux desktop environment (XFCE + TigerVNC + noVNC + Chrome), enabling Hermes Agent to run browser and GUI automation inside the container. All configuration and data persist in the local `./data` directory.

## Features

- **Gateway**: Main Hermes Agent service (default port `8642`)
- **Dashboard**: Web management UI (default port `9119`)
- **noVNC**: Browser-based remote desktop (default HTTP `6081`, WebSocket `6080`)
- **Chrome**: Browser automation for the agent (Google Chrome on amd64, Chromium on other architectures)
- **Zhuyin input**: IBus Chewing for Traditional Chinese input on the XFCE desktop, with Noto CJK fonts so Chinese renders in the desktop and Chrome
- **GUI automation packages**: Pre-installed `pyautogui`, `pynput`, `Pillow`, and `crawl4ai` for screen control and web scraping
- **SearXNG**: Self-hosted metasearch instance wired up as Hermes' `web_search` backend, so search needs no third-party API key (UI on `127.0.0.1:18080`)

## Requirements

- Docker Engine 24+ and Docker Compose v2
- Recommended: at least **8 GB RAM** and **4 CPUs** (GUI + browser workloads are resource-heavy)
- **Windows**: [Docker Desktop](https://www.docker.com/products/docker-desktop/) with WSL2 backend; run the commands below from WSL or Git Bash

## Quick Start

### 1. Copy environment config

```bash
cp .env.example .env
```

Windows PowerShell:

```powershell
Copy-Item .env.example .env
```

Edit `.env` and change at least `HERMES_DASHBOARD_BASIC_AUTH_PASSWORD` and `VNC_PASSWORD` (do not keep the default `change-me`).

### 2. First-time setup (interactive wizard)

Run `setup` with the official image to write API keys and other settings into `./data`:

**Linux / macOS / WSL:**

```bash
HERMES_UID=$(id -u) HERMES_GID=$(id -g) docker compose --profile setup run --rm setup
```

**Windows (when `id` is unavailable):**

Set `HERMES_UID` / `HERMES_GID` in `.env` (usually `1000` inside WSL), then:

```bash
docker compose --profile setup run --rm setup
```

### 3. Build and start

```bash
HERMES_UID=$(id -u) HERMES_GID=$(id -g) docker compose up -d --build
```

Or, if UID/GID are already set in `.env`:

```bash
docker compose up -d --build
```

### 4. Open services

| Service | Default URL |
|---------|-------------|
| noVNC desktop | http://localhost:6081/vnc_lite.html?host=localhost&port=6080 |
| Dashboard | http://localhost:9119 |
| Gateway | http://localhost:8642 |
| SearXNG | http://localhost:18080 |

## Web search backend

`docker compose up` also starts a [SearXNG](https://docs.searxng.org/) instance and points Hermes at it through `SEARXNG_URL=http://searxng:8080`, resolved over the compose network. Tell Hermes to use it by setting the backend in `data/config.yaml`:

```yaml
web:
  search_backend: "searxng"
```

Notes:

- Config lives in [`docker/searxng/settings.yml`](docker/searxng/settings.yml) and is mounted read-only. It sets `use_default_settings: true`, so the engine list comes from the image; only the overrides are tracked.
- `formats` must include `json` — Hermes calls `/search?format=json`, which returns 403 when only `html` is enabled (the web UI keeps working, which makes this easy to misdiagnose).
- Set `SEARXNG_SECRET` in `.env` (`openssl rand -hex 32`). SearXNG refuses to start on the upstream default secret; compose ships a local-only fallback so the stack comes up without configuration.
- SearXNG queries public engines, which rate-limit and serve CAPTCHAs. Heavy automated searching will get engines temporarily suspended — check `unresponsive_engines` in the JSON response when results come back empty.

## Migrate from local Hermes (optional)

If you previously installed Hermes Agent natively on Windows, use [`scripts/migrate-local-hermes.py`](scripts/migrate-local-hermes.py) to merge models, API keys, skills, and profiles into `./data`:

1. Complete **first-time setup** (`setup`) above so `./data/config.yaml` exists
2. Run the migration — the script reads `%LOCALAPPDATA%\hermes` by default and declares PyYAML inline, so `uv run` installs it for you:

```bash
uv run scripts/migrate-local-hermes.py
```

To migrate from a different location, set `LOCAL_HERMES`:

```bash
LOCAL_HERMES=/path/to/hermes uv run scripts/migrate-local-hermes.py
```

The script backs up `data/config.yaml` and rewrites `localhost` URLs to `host.docker.internal` for in-container connectivity.

## Common commands

```bash
# View logs
docker compose logs -f gateway

# Stop
docker compose down

# Rebuild image only
docker compose build gateway

# Pull upstream image and rebuild
docker compose build --pull gateway

# Manually restart GUI inside container (debug)
docker compose exec gateway /docker/gui/hermes-vnc-restart.sh
```

## Environment variables

See [`.env.example`](.env.example) for a full template.

| Variable | Description | Default |
|----------|-------------|---------|
| `HERMES_UID` / `HERMES_GID` | Match host user to avoid `./data` permission issues | `10000` in compose; `1000` in `.env.example` |
| `TZ` | Container timezone | `Asia/Taipei` |
| `HERMES_GATEWAY_PORT` | Gateway host port | `8642` |
| `HERMES_DASHBOARD_PORT` | Dashboard host port | `9119` |
| `HERMES_VNC_PORT` | VNC host port | `5901` |
| `HERMES_NOVNC_WS_PORT` | noVNC WebSocket host port | `6080` |
| `HERMES_NOVNC_HTTP_PORT` | noVNC HTTP host port | `6081` |
| `HERMES_GUI_BIND_ADDRESS` | Host interface for the VNC / noVNC ports | `127.0.0.1` |
| `HERMES_SEARXNG_PORT` | SearXNG host port (bound to `127.0.0.1`) | `18080` |
| `SEARXNG_SECRET` | SearXNG secret key; it will not start without one | local-only fallback |
| `SEARXNG_URL` | Where Hermes looks for SearXNG | `http://searxng:8080` |
| `HERMES_DASHBOARD` | Enable Dashboard | `1` |
| `HERMES_DASHBOARD_BASIC_AUTH_*` | Dashboard basic auth | — |
| `VNC_PASSWORD` | VNC password (written only on first passwd file creation; truncated to 8 characters by the VNC protocol) | — |
| `VNC_DISPLAY` / `VNC_PORT` / `VNC_GEOMETRY` | VNC display, container-side port, resolution | `:1` / `5901` / `1920x1080` |
| `HERMES_MEMORY_LIMIT` / `HERMES_CPU_LIMIT` | Resource limits (see below) | `8G` / `4.0` |

### UID / GID

`HERMES_UID` and `HERMES_GID` should match the user running Docker so the in-container `hermes` user owns files under `./data` correctly.

- **Linux / WSL**: `id -u` and `id -g`
- **macOS**: Usually `501` / `20`, or whatever `id` reports
- **Windows + Docker Desktop**: Use WSL UID when working inside WSL; keep `1000` from `.env.example` when mounting from the Windows filesystem only

### Resource limits

`deploy.resources.limits` in `docker-compose.yml` **only applies in Docker Swarm mode**. A normal `docker compose up` does not enforce memory/CPU caps; adjust limits in Docker Desktop settings or use Swarm if needed.

The container also sets `shm_size: 2g` for Chrome and GUI processes.

## Project structure

```
.
├── docker-compose.yml          # Service definitions (gateway, searxng, setup)
├── Dockerfile.gui              # Derived image: official Hermes + desktop stack
├── .env.example                # Environment variable template
├── .gitattributes              # Enforce LF line endings for shell / s6 scripts
├── data/                       # Persistent data (gitignored, created on first run)
├── scripts/
│   └── migrate-local-hermes.py # Migrate local Hermes settings into ./data
└── docker/
    ├── gui/
    │   ├── cont-init-vnc.sh    # Prepare VNC config on container start
    │   ├── hermes-vnc-restart.sh # Manual GUI stack restart (debug)
    │   ├── xstartup.default    # XFCE + IBus session
    │   └── s6-gui-stack/       # s6 long-running services: VNC + noVNC
    └── searxng/
        └── settings.yml        # SearXNG overrides (mounted read-only)
```

## Security

1. **Do not expose VNC / noVNC ports to the public internet.** By default `5901`, `6080`, and `6081` bind to `127.0.0.1` only. Setting `HERMES_GUI_BIND_ADDRESS=0.0.0.0` publishes the desktop on every host interface, guarded by nothing but an 8-character VNC password — only do that on a trusted network.
2. **Change default passwords** for `VNC_PASSWORD` and `HERMES_DASHBOARD_BASIC_AUTH_PASSWORD`.
3. **When exposing Dashboard externally**, enable Basic Auth and set `HERMES_DASHBOARD_BASIC_AUTH_SECRET` (generate with `openssl rand -hex 32`) for stable sessions.
4. **VNC password is written only on first boot** to `data/.vnc/passwd` and `data/.config/tigervnc/passwd`. To change it, delete both files, update `VNC_PASSWORD` in `.env`, and restart the container.

## Troubleshooting

### noVNC black screen or connection failure

```bash
docker compose logs gateway
docker compose exec gateway /docker/gui/hermes-vnc-restart.sh
```

Ensure ports `6080` and `6081` are not in use by another process.

### `./data` permission errors

Verify `HERMES_UID` / `HERMES_GID` in `.env` match the host user, then re-run setup or fix ownership:

```bash
sudo chown -R "$(id -u):$(id -g)" ./data
```

### Line endings on Windows

The project uses `.gitattributes` and CRLF stripping in `Dockerfile.gui` so shell / s6 scripts run correctly in Linux containers. If you edit scripts under `docker/gui/` on Windows, save them with LF line endings.

### Reach host services (e.g. Ollama)

The container defines `host.docker.internal:host-gateway`. The agent can reach host services at `http://host.docker.internal:<port>`.

### Update upstream Hermes Agent

```bash
docker compose build --pull gateway
docker compose up -d
```

## License

This project is a containerized packaging of Hermes Agent. For Hermes Agent itself, see the upstream [Nous Research](https://github.com/NousResearch/hermes-agent) project license.
