# Hermes Agent GUI Container

**English** | [中文說明](README.zh-TW.md)

A Docker setup that extends the official [nousresearch/hermes-agent](https://hub.docker.com/r/nousresearch/hermes-agent) image with a Linux desktop environment (XFCE + TigerVNC + noVNC + Chrome), enabling Hermes Agent to run browser and GUI automation inside the container. All configuration and data persist in the local `./data` directory.

## Features

- **Gateway**: Main Hermes Agent service (default port `8642`)
- **Dashboard**: Web management UI (default port `9119`)
- **noVNC**: Browser-based remote desktop (default HTTP `6081`, WebSocket `6080`)
- **Chrome**: Browser automation for the agent (Google Chrome on amd64, Chromium on other architectures)
- **Zhuyin input**: IBus Chewing for Traditional Chinese input on the XFCE desktop
- **GUI automation packages**: Pre-installed `pyautogui`, `pynput`, `Pillow`, and `crawl4ai` for screen control and web scraping

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

## Migrate from local Hermes (optional)

If you previously installed Hermes Agent natively on Windows, use [`scripts/migrate-local-hermes.py`](scripts/migrate-local-hermes.py) to merge models, API keys, skills, and profiles into `./data`:

1. Edit `LOCAL_HERMES` at the top of the script to point at your local Hermes data directory (default: `%LOCALAPPDATA%\hermes`)
2. Complete **first-time setup** (`setup`) above so `./data/config.yaml` exists
3. Run the migration (requires PyYAML):

```bash
uv run scripts/migrate-local-hermes.py
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
| `HERMES_DASHBOARD` | Enable Dashboard | `1` |
| `HERMES_DASHBOARD_BASIC_AUTH_*` | Dashboard basic auth | — |
| `VNC_PASSWORD` | VNC password (written only on first passwd file creation) | — |
| `VNC_DISPLAY` / `VNC_PORT` / `VNC_GEOMETRY` | VNC display, port, resolution | `:1` / `5901` / `1920x1080` |
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
├── docker-compose.yml          # Service definitions (gateway, setup)
├── Dockerfile.gui              # Derived image: official Hermes + desktop stack
├── .env.example                # Environment variable template
├── .gitattributes              # Enforce LF line endings for shell / s6 scripts
├── data/                       # Persistent data (gitignored, created on first run)
├── scripts/
│   └── migrate-local-hermes.py # Migrate local Hermes settings into ./data
└── docker/gui/
    ├── cont-init-vnc.sh        # Prepare VNC config on container start
    ├── hermes-vnc-restart.sh   # Manual GUI stack restart (debug)
    ├── xstartup.default        # XFCE + IBus session
    └── s6-gui-stack/           # s6 long-running services: VNC + noVNC
```

## Security

1. **Do not expose VNC / noVNC ports to the public internet.** Defaults map `5901`, `6080`, and `6081` to the host; use only on trusted localhost or private networks.
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
