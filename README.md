# Hermes Agent — Ubuntu + GUI 自訂 Docker 部署

自訂 **Ubuntu 24.04** 映像，內含 **XFCE 桌面**、**TigerVNC** 與 **noVNC**（瀏覽器即可操作 GUI），並透過 [官方 install.sh](https://github.com/NousResearch/hermes-agent/blob/main/scripts/install.sh) 安裝 Hermes Agent。

與官方 `nousresearch/hermes-agent`（Debian + s6）不同，此映像適合需要：

- 可自訂的 Ubuntu 基底與建置參數
- 容器內完整圖形桌面（**預裝 Google Chrome**、Playwright 有頭模式等）
- 透過 noVNC 遠端操作桌面

## 架構

```
┌─────────────────────────────────────────────┐
│  Ubuntu 24.04 容器                           │
│  ├─ XFCE4 (TigerVNC :1)                     │
│  ├─ noVNC → :6080/vnc.html                   │
│  ├─ Hermes Gateway → :8642                   │
│  └─ Hermes Dashboard → :9119               │
│  Volume: ./data → /opt/data                  │
└─────────────────────────────────────────────┘
```

## 快速開始

```bash
cd /home/efai/bear/hermes_container
cp .env.example .env

# 建議修改 VNC_PASSWORD 後再建置
export HERMES_UID=$(id -u) HERMES_GID=$(id -g)

# 建置映像（首次約 10–20 分鐘，視網路而定）
docker compose build

mkdir -p ./data
docker compose --profile setup run --rm setup

docker compose up -d
```

### 存取 GUI

| 方式 | 網址 |
|------|------|
| **noVNC（建議）** | http://127.0.0.1:6080/vnc.html（VNC 密碼見 `.env` 的 `VNC_PASSWORD`，預設 `hermes`） |

桌面有 **Hermes Chat**、**Hermes Setup** 捷徑；終端機可直接執行 `hermes`。

> `./data` volume 會覆蓋映像內設定。首次啟動會自動還原 `.env`、`config.yaml`。若需重設 API Key：
> ```bash
> docker compose --profile setup run --rm setup
> ```
| VNC 客戶端 | `127.0.0.1:5901`（密碼見 `.env` 的 `VNC_PASSWORD`） |
| Hermes Dashboard | http://127.0.0.1:9119 |

桌面選單或終端機可啟動 **Google Chrome**；命令列：

```bash
docker exec -it hermes chrome
# 或
docker exec -u hermes -e DISPLAY=:1 hermes /usr/local/bin/chrome
```

> **amd64**：安裝官方 `google-chrome-stable`。**ARM64** 建置時會改裝 `chromium-browser` 並建立相容 symlink。

## 自訂映像建置參數

在 `.env` 或 `docker compose build` 時設定：

| 變數 | 說明 | 預設 |
|------|------|------|
| `UBUNTU_VERSION` | Ubuntu 版本 | `24.04` |
| `HERMES_BRANCH` | Hermes git 分支 | `main` |
| `HERMES_COMMIT` | 釘選 commit | （空） |
| `VNC_PASSWORD` | VNC 密碼（建置時寫入） | `hermes` |
| `HERMES_SKIP_BROWSER` | `1` = 不裝 Playwright | `0` |
| `HERMES_UID` / `HERMES_GID` | 容器內 hermes 使用者 | `1000` |

範例：指定分支並略過瀏覽器

```bash
HERMES_BRANCH=main HERMES_SKIP_BROWSER=1 docker compose build
```

## 修改 Dockerfile

主要檔案：

| 檔案 | 用途 |
|------|------|
| `Dockerfile` | Ubuntu 基底、GUI 套件、Hermes 安裝 |
| `docker/entrypoint.sh` | 啟動 dbus、VNC、noVNC、Hermes |
| `docker/vnc-xstartup` | XFCE 工作階段 |

可在 `Dockerfile` 的 `apt-get install` 區塊加入額外套件，或調整 `HERMES_BRANCH` / `HERMES_COMMIT` 安裝不同版本。

## 連接本機 Ollama

容器內的 Hermes 無法用 `localhost:11434` 連宿主機 Ollama，請用 **`host.docker.internal`**。

在 `.env` 加入（並確認宿主機已 `ollama serve`）：

```bash
OLLAMA_BASE_URL=http://host.docker.internal:11434/v1
OLLAMA_MODEL=llama3.2
OLLAMA_CONTEXT_LENGTH=65536
```

重啟後會自動寫入 `./data/config.yaml`。也可在 Compose 內跑 Ollama：`docker compose --profile ollama up -d`。

詳見 [docs/ollama.md](docs/ollama.md)。

## SearXNG 搜尋（選用）

```bash
# .env
SEARXNG_URL=http://searxng:8080

docker compose --profile searxng up -d --force-recreate
```

Hermes 會使用 `web_search` 工具透過 SearXNG 搜尋。詳見 [docs/searxng.md](docs/searxng.md)。

## 常用指令

```bash
docker compose logs -f gateway
docker compose build --no-cache          # 完整重建
docker exec -it hermes bash              # 進入容器 shell
docker compose run --rm gateway gui-only # 只啟動 GUI、不跑 Hermes
```

## 以 root 執行 Hermes（權限等同 root）

預設以 `hermes` 使用者（uid 1000）執行，較安全。若需要與 root 相同權限（安裝套件、寫入任意路徑、避免 volume 權限問題），在 `.env` 設定：

```bash
HERMES_RUN_AS_ROOT=1
```

然後重建並啟動：

```bash
docker compose up -d --force-recreate
```

此模式下：

- Gateway、CLI、Setup 皆以 **root** 執行
- 自動設定 `HERMES_ALLOW_ROOT_GATEWAY=1`（Hermes 官方允許 root gateway 的開關）
- noVNC 桌面也是 root 工作階段

**安全提醒**：容器內 root 幾乎等同於在宿主機上擁有完整容器權限。勿對外暴露埠口，勿在生產環境隨意開啟。

若還需要操作**宿主機 Docker**，可額外掛載 socket（高風險，僅限信任環境）：

```yaml
# docker-compose.yml → gateway.volumes 加入：
#   - /var/run/docker.sock:/var/run/docker.sock
```

## 權限問題（常見）

若曾用 `docker exec hermes hermes setup`（root）或 root 執行設定，`.env` 可能變成 `root:root`，導致 Hermes 崩潰。

**修正**（重建後會自動修，或手動）：

```bash
docker compose up -d --force-recreate
# 或
docker exec hermes /usr/local/bin/fix-data-permissions.sh
```

**正確做法**：

- 設定：`docker compose --profile setup run --rm setup`（以 hermes 使用者執行）
- 或 VNC 桌面點 **Hermes Setup**
- 避免：`docker exec hermes hermes ...`（root 會寫壞權限；已用 shim 緩解，重建映像後 `hermes` 會自動降權）


| 項目 | 本專案 | 官方 `nousresearch/hermes-agent` |
|------|--------|----------------------------------|
| 基底 | Ubuntu 24.04 | Debian 13 |
| PID 1 / 監督 | entrypoint + `--no-supervise` | s6-overlay |
| GUI | XFCE + VNC + noVNC | 無（僅 headless） |
| 建置 | 本地 `docker compose build` | 拉取預建映像 |

若需要官方 s6 多 profile 監督，可改回使用 `nousresearch/hermes-agent:latest` 映像。

## 安全提醒

- 預設僅綁定 `127.0.0.1`；遠端請用 SSH tunnel 或反向代理 + TLS。
- `VNC_PASSWORD` 在建置時寫入映像，變更後需 `docker compose build`。
- 勿將 `.env` 或 `./data` 提交至 git。

## 參考

- [Hermes Docker 文件](https://hermes-agent.nousresearch.com/docs/user-guide/docker)
- [Hermes 安裝指南](https://hermes-agent.nousresearch.com/docs/getting-started/installation)
