# Hermes Agent GUI Container

在官方 [nousresearch/hermes-agent](https://hub.docker.com/r/nousresearch/hermes-agent) 映像之上，加上 Linux 桌面環境（XFCE + TigerVNC + noVNC + Chrome），讓 Hermes Agent 能在容器內使用瀏覽器與 GUI 自動化。所有設定與資料持久化於本機 `./data` 目錄。

## 功能

- **Gateway**：Hermes Agent 主要服務（預設 port `8642`）
- **Dashboard**：Web 管理介面（預設 port `9119`）
- **noVNC**：瀏覽器遠端桌面（預設 HTTP `6081`、WebSocket `6080`）
- **Chrome**：Agent 瀏覽器自動化（amd64 為 Google Chrome，其他架構為 Chromium）
- **注音輸入**：IBus Chewing，可在 XFCE 桌面使用

## 需求

- Docker Engine 24+ 與 Docker Compose v2
- 建議至少 **8 GB RAM**、**4 CPU**（GUI + 瀏覽器負載較高）
- **Windows**：建議使用 [Docker Desktop](https://www.docker.com/products/docker-desktop/) + WSL2 backend，在 WSL 或 Git Bash 中執行下方指令

## 快速開始

### 1. 複製環境設定

```bash
cp .env.example .env
```

Windows PowerShell：

```powershell
Copy-Item .env.example .env
```

編輯 `.env`，至少修改 `HERMES_DASHBOARD_BASIC_AUTH_PASSWORD` 與 `VNC_PASSWORD`（勿使用預設的 `change-me`）。

### 2. 首次設定（互動式精靈）

使用官方映像執行 `setup`，將 API 金鑰等設定寫入 `./data`：

**Linux / macOS / WSL：**

```bash
HERMES_UID=$(id -u) HERMES_GID=$(id -g) docker compose --profile setup run --rm setup
```

**Windows（無 `id` 指令時）：**

在 `.env` 設定 `HERMES_UID` / `HERMES_GID`（WSL 內通常為 `1000`），然後：

```bash
docker compose --profile setup run --rm setup
```

### 3. 建置並啟動

```bash
HERMES_UID=$(id -u) HERMES_GID=$(id -g) docker compose up -d --build
```

或已於 `.env` 設定 UID/GID 時：

```bash
docker compose up -d --build
```

### 4. 開啟服務

| 服務 | 預設網址 |
|------|----------|
| noVNC 桌面 | http://localhost:6081/vnc_lite.html?host=localhost&port=6080 |
| Dashboard | http://localhost:9119 |
| Gateway | http://localhost:8642 |

## 常用指令

```bash
# 查看日誌
docker compose logs -f gateway

# 停止
docker compose down

# 僅重建映像
docker compose build gateway

# 拉取上游映像後重建
docker compose build --pull gateway

# 容器內手動重啟 GUI（除錯用）
docker compose exec gateway /docker/gui/hermes-vnc-restart.sh
```

## 環境變數

完整範例見 [`.env.example`](.env.example)。

| 變數 | 說明 | 預設 |
|------|------|------|
| `HERMES_UID` / `HERMES_GID` | 對應主機使用者，避免 `./data` 權限錯亂 | `10000` |
| `HERMES_GATEWAY_PORT` | Gateway 對外 port | `8642` |
| `HERMES_DASHBOARD_PORT` | Dashboard 對外 port | `9119` |
| `HERMES_DASHBOARD` | 啟用 Dashboard | `1` |
| `HERMES_DASHBOARD_BASIC_AUTH_*` | Dashboard 基本認證 | — |
| `VNC_PASSWORD` | VNC 密碼（僅在首次建立 `data/.vnc/passwd` 時寫入） | — |
| `VNC_GEOMETRY` | 桌面解析度 | `1920x1080` |
| `HERMES_MEMORY_LIMIT` / `HERMES_CPU_LIMIT` | 資源上限（見下方說明） | `8G` / `4.0` |

### UID / GID 說明

`HERMES_UID` 與 `HERMES_GID` 應與執行 Docker 的使用者一致，容器內 `hermes` 使用者才會正確擁有 `./data` 下的檔案。

- **Linux / WSL**：`id -u` 與 `id -g`
- **macOS**：通常為 `501` / `20`，或依 `id` 輸出為準
- **Windows + Docker Desktop**：在 WSL 內操作時用 WSL 的 UID；若只在 Windows 檔案系統掛載，可維持 `.env.example` 的 `1000`

### 資源限制說明

`docker-compose.yml` 中的 `deploy.resources.limits` **僅在 Docker Swarm 模式下生效**。一般 `docker compose up` 不會套用記憶體與 CPU 上限；若需限制，請在 Docker Desktop 設定中調整，或改用 Swarm。

## 專案結構

```
.
├── docker-compose.yml      # 服務定義（gateway、setup）
├── Dockerfile.gui          # 衍生映像：官方 Hermes + 桌面環境
├── .env.example            # 環境變數範本
├── data/                   # 持久化資料（git 忽略，首次執行後產生）
└── docker/gui/
    ├── cont-init-vnc.sh    # 容器啟動時準備 VNC 設定
    ├── hermes-vnc-restart.sh
    ├── xstartup.default    # XFCE + IBus 工作階段
    └── s6-gui-stack/       # s6 長駐服務：VNC + noVNC
```

## 安全注意事項

1. **勿將 VNC / noVNC port 暴露到公網**。預設會對外映射 `5901`、`6080`、`6081`；僅在受信任的本機或內網使用。
2. **務必修改預設密碼**：`VNC_PASSWORD` 與 Dashboard 的 `HERMES_DASHBOARD_BASIC_AUTH_PASSWORD`。
3. **Dashboard 對外服務時**請設定 Basic Auth，並建議設定 `HERMES_DASHBOARD_BASIC_AUTH_SECRET`（可用 `openssl rand -hex 32` 產生）以維持 session 穩定。
4. **VNC 密碼僅在首次啟動寫入**。若要變更，刪除 `data/.vnc/passwd` 後修改 `.env` 中的 `VNC_PASSWORD` 再重啟容器。

## 疑難排解

### noVNC 黑畫面或連不上

```bash
docker compose logs gateway
docker compose exec gateway /docker/gui/hermes-vnc-restart.sh
```

確認 port `6080`、`6081` 未被其他程式佔用。

### `./data` 權限錯誤

確認 `.env` 的 `HERMES_UID` / `HERMES_GID` 與主機使用者一致後，重新執行 setup 或調整目錄擁有者：

```bash
sudo chown -R "$(id -u):$(id -g)" ./data
```

### 連接主機上的服務（如 Ollama）

容器已設定 `host.docker.internal:host-gateway`，Agent 可透過 `http://host.docker.internal:<port>` 存取主機服務。

### 更新上游 Hermes Agent

```bash
docker compose build --pull gateway
docker compose up -d
```

## 授權

本專案為 Hermes Agent 的容器化封裝；Hermes Agent 本身請參考 [Nous Research](https://github.com/NousResearch/hermes-agent) 上游專案之授權條款。
