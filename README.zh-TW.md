# Hermes Agent GUI Container

[English](README.md) | **中文說明**

在官方 [nousresearch/hermes-agent](https://hub.docker.com/r/nousresearch/hermes-agent) 映像之上，加上 Linux 桌面環境（XFCE + TigerVNC + noVNC + Chrome），讓 Hermes Agent 能在容器內使用瀏覽器與 GUI 自動化。所有設定與資料持久化於本機 `./data` 目錄。

## 功能

- **Gateway**：Hermes Agent 主要服務（預設 port `8642`）
- **Dashboard**：Web 管理介面（預設 port `9119`）
- **noVNC**：瀏覽器遠端桌面，網頁與 WebSocket 共用同一個 port（預設 `6080`）
- **Chrome**：Agent 瀏覽器自動化（amd64 為 Google Chrome，其他架構為 Chromium）
- **注音輸入**：IBus Chewing，可在 XFCE 桌面使用；並預裝 Noto CJK 字型，桌面與 Chrome 都能正常顯示中文
- **GUI 自動化套件**：映像內預裝 `pyautogui`、`pynput`、`Pillow`、`crawl4ai`，支援螢幕操作與網頁擷取
- **SearXNG**：自架元搜尋實例，已接成 Hermes 的 `web_search` 後端，搜尋不需任何第三方 API 金鑰（UI 在 `127.0.0.1:18080`）

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
| noVNC 桌面 | http://localhost:6080/vnc_lite.html |
| Dashboard | http://localhost:9119 |
| Gateway | http://localhost:8642 |
| SearXNG | http://localhost:18080 |

## `./data` 內的 Agent 設定

setup 精靈會產生 `data/config.yaml`，但不會寫入本容器自有能力的相關設定。`./data` 是 git 忽略的，所以這些步驟不會隨著 clone 一起帶走 —— 在新環境部署時要重做一次。

**1. 合併設定片段。** [`examples/config-additions.yaml`](examples/config-additions.yaml) 內含視覺模型、SearXNG 後端與桌面控制三個區塊。請**合併**進 `data/config.yaml`，不要覆蓋 —— 精靈產生的那份檔案裡有你的 API 金鑰。

**2. 檢查 `agent.disabled_toolsets`。** 精靈可能會停用本容器依賴的工具集。`computer_use`、`vision`、`web`、`browser` 不能出現在該清單裡，否則功能會無聲失效 —— agent 會回你「沒有截圖工具」而不是報錯。

**3. 複製 agent 常駐指示。** [`examples/SOUL.md`](examples/SOUL.md) → `data/SOUL.md`。Hermes 會把 `HERMES_HOME` 下的 `SOUL.md` 注入每一次的系統提示；內容告訴 agent 它有桌面可用，以及如何把檔案透過對話回傳（`MEDIA:/opt/data/shot.png`）。`.hermes.md` / `AGENTS.md` 是從**工作目錄**讀取的，在這個環境下位置不可靠。

**4. 安裝 cua-driver**（選用 —— 下方的 `hermes-desktop` 已涵蓋多數桌面控制需求）：

```bash
docker compose exec gateway /opt/hermes/.venv/bin/hermes computer-use install
docker compose exec gateway /opt/hermes/.venv/bin/hermes computer-use doctor
```

它會裝在 `/opt/data/.local/bin`，因此會隨 `./data` 持久化，重建映像也不會消失。`doctor` 顯示 `ax_capability` 受阻是預期的：容器內沒有 AT-SPI，所以元素樹是空的，但螢幕擷取與輸入注入都正常。

### 視覺模型

任何 OpenAI 相容端點皆可，設定完全來自 `.env`：

```bash
AUXILIARY_VISION_BASE_URL=http://host.docker.internal:11434/v1
AUXILIARY_VISION_MODEL=qwen3.5:9b
AUXILIARY_VISION_API_KEY=ollama
AUXILIARY_VISION_REASONING_EFFORT=none
```

`host.docker.internal` 可直達主機，所以本機的 Ollama 不需要任何 port mapping —— 但它必須監聽在 loopback 以外的介面（`OLLAMA_HOST=0.0.0.0`）。

具備 thinking 能力的模型請設定 `AUXILIARY_VISION_REASONING_EFFORT=none`。否則它會把整個 token 預算花在 reasoning 欄位上而回傳空的 content，症狀是視覺分析靜靜地回傳空白。

視覺模型會不會真的被使用，取決於主模型：當主模型的供應商原生支援在 tool result 裡夾帶圖片（Anthropic、OpenAI、OpenRouter、Gemini 3）時，Hermes 會把截圖直接交給主模型，這個端點就不會被呼叫。custom 與本地供應商則會走這條 auxiliary 路徑。

### 不靠像素的桌面控制

`hermes-desktop` 透過 AT-SPI 讀取真實的 widget 樹，用 ref 定位元素並提供螢幕絕對座標 —— 相當於瀏覽器之外的 `browser_snapshot`。它存在的理由是視覺模型無法提供可用的座標：模型在自己內部縮放後的空間裡回報位置，在 1440x900 的畫面上實測誤差 231–475 px，而 AT-SPI 能精準命中 39x25 的選單項目。

```bash
docker compose exec -u hermes gateway hermes-desktop snapshot
docker compose exec -u hermes gateway hermes-desktop click d3
```

```
# xfce4-panel
  - toggle button "Applications" [ref=d3] (0,0 102x26)
```

相依項目已接進映像與桌面 session：映像安裝了 `at-spi2-core` 與 `python3-pyatspi`，`xstartup` 把 session bus 發佈在 `/run/user/$HERMES_UID/bus` 並啟動 AT-SPI bus launcher，compose 則傳入 `DBUS_SESSION_BUS_ADDRESS` 讓 agent 找得到。應用程式會自動加入該 bus，包含 agent 自己啟動的。

請以 `hermes` 身分執行。D-Bus 的 peer 連線屬於該使用者，root 會看到所有應用都是 `role=invalid`。agent 本身就是以 `hermes` 執行。

注意 `cont-init` 只在 `data/.vnc/xstartup` 不存在時才安裝 `xstartup.default`，既有的 session 檔案不會被覆寫 —— 所以更新該檔後，需要先把舊的移開再重啟容器。

## 網頁搜尋後端

`docker compose up` 會一併啟動 [SearXNG](https://docs.searxng.org/) 實例，並透過 `SEARXNG_URL=http://searxng:8080`（走 compose 網路解析）讓 Hermes 使用它。在 `data/config.yaml` 設定 `web.search_backend: "searxng"` 即可啟用（見上方步驟 1）。

注意事項：

- 設定檔在 [`docker/searxng/settings.yml`](docker/searxng/settings.yml)，以唯讀方式掛載。它設了 `use_default_settings: true`，引擎清單來自映像本身，版控裡只放覆寫項目。
- `formats` 必須包含 `json` —— Hermes 呼叫的是 `/search?format=json`，只開 `html` 時該請求會回 403，但網頁 UI 仍然正常，因此很容易誤判。
- 請在 `.env` 設定 `SEARXNG_SECRET`（`openssl rand -hex 32`）。SearXNG 拒絕以上游預設 secret 啟動；compose 提供了一個僅供本機使用的 fallback，讓服務不必設定就能起來。
- SearXNG 查詢的是公開引擎，會遇到速率限制與 CAPTCHA。大量自動化搜尋會讓引擎被暫時停用 —— 結果為空時，檢查 JSON 回應中的 `unresponsive_engines`。

## 從本機 Hermes 遷移設定（選用）

若先前已在 Windows 本機安裝 Hermes Agent，可使用 [`scripts/migrate-local-hermes.py`](scripts/migrate-local-hermes.py) 將模型、API 金鑰、skills 與 profiles 合併至 `./data`：

1. 先完成上述 **首次設定**（`setup`），確保 `./data/config.yaml` 已存在
2. 執行遷移 —— 腳本預設讀取 `%LOCALAPPDATA%\hermes`，並以 inline metadata 宣告 PyYAML，`uv run` 會自動安裝：

```bash
uv run scripts/migrate-local-hermes.py
```

若要從其他位置遷移，設定 `LOCAL_HERMES`：

```bash
LOCAL_HERMES=/path/to/hermes uv run scripts/migrate-local-hermes.py
```

腳本會自動備份 `data/config.yaml`，並將 `localhost` URL 改寫為 `host.docker.internal` 以在容器內正常連線。

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
| `HERMES_UID` / `HERMES_GID` | 對應主機使用者，避免 `./data` 權限錯亂 | `1000` |
| `TZ` | 容器時區 | `Asia/Taipei` |
| `HERMES_GATEWAY_PORT` | Gateway 對外 port | `8642` |
| `HERMES_DASHBOARD_PORT` | Dashboard 對外 port | `9119` |
| `HERMES_VNC_PORT` | VNC 對外 port | `5901` |
| `HERMES_NOVNC_PORT` | noVNC 對外 port（網頁 + WebSocket） | `6080` |
| `HERMES_GUI_BIND_ADDRESS` | VNC / noVNC port 綁定的主機介面 | `127.0.0.1` |
| `HERMES_SEARXNG_PORT` | SearXNG 對外 port（綁定 `127.0.0.1`） | `18080` |
| `SEARXNG_SECRET` | SearXNG secret key，未設定則無法啟動 | 僅本機用的 fallback |
| `SEARXNG_URL` | Hermes 尋找 SearXNG 的位址 | `http://searxng:8080` |
| `AUXILIARY_VISION_*` | 視覺端點：`_BASE_URL`、`_MODEL`、`_API_KEY`、`_REASONING_EFFORT` | 空（自動選擇） |
| `HERMES_DASHBOARD` | 啟用 Dashboard | `1` |
| `HERMES_DASHBOARD_BASIC_AUTH_*` | Dashboard 基本認證 | — |
| `VNC_PASSWORD` | VNC 密碼（僅在首次建立 passwd 檔時寫入；VNC 協定只取前 8 個字元） | — |
| `VNC_DISPLAY` / `VNC_PORT` / `VNC_GEOMETRY` | VNC 顯示編號、容器內 port、解析度 | `:1` / `5901` / `1920x1080` |
| `HERMES_MEMORY_LIMIT` / `HERMES_CPU_LIMIT` | 資源上限（見下方說明） | `8G` / `4.0` |

### UID / GID 說明

`HERMES_UID` 與 `HERMES_GID` 應與執行 Docker 的使用者一致，容器內 `hermes` 使用者才會正確擁有 `./data` 下的檔案。映像內建的 `hermes` 使用者是 UID 10000，entrypoint 會依這兩個變數重新映射，因此這裡的預設值是 `1000` 而非映像的 10000。

- **Linux / WSL**：`id -u` 與 `id -g`
- **macOS**：通常為 `501` / `20`，或依 `id` 輸出為準
- **Windows + Docker Desktop**：在 WSL 內操作時用 WSL 的 UID；若只在 Windows 檔案系統掛載，可維持 `.env.example` 的 `1000`

### 資源限制說明

`docker-compose.yml` 中的 `deploy.resources.limits` **僅在 Docker Swarm 模式下生效**。一般 `docker compose up` 不會套用記憶體與 CPU 上限；若需限制，請在 Docker Desktop 設定中調整，或改用 Swarm。

容器另設定 `shm_size: 2g`，供 Chrome 與 GUI 程序使用共享記憶體。

## 專案結構

```
.
├── docker-compose.yml          # 服務定義（gateway、searxng、setup）
├── Dockerfile.gui              # 衍生映像：官方 Hermes + 桌面環境
├── .env.example                # 環境變數範本
├── .gitattributes              # 強制 shell / s6 腳本使用 LF 換行
├── data/                       # 持久化資料（git 忽略，首次執行後產生）
├── examples/
│   ├── SOUL.md                 # Agent 常駐指示 → 複製到 data/SOUL.md
│   └── config-additions.yaml   # 合併進 data/config.yaml 的設定片段
├── scripts/
│   └── migrate-local-hermes.py # 本機 Hermes 設定遷移至 ./data
└── docker/
    ├── gui/
    │   ├── cont-init-vnc.sh    # 容器啟動時準備 VNC 設定
    │   ├── hermes-vnc-restart.sh # 手動重啟 GUI stack（除錯用）
    │   ├── xstartup.default    # XFCE + IBus 工作階段
    │   └── s6-gui-stack/       # s6 長駐服務：VNC + noVNC
    └── searxng/
        └── settings.yml        # SearXNG 覆寫設定（唯讀掛載）
```

## 安全注意事項

1. **勿將 VNC / noVNC port 暴露到公網**。預設 `5901`、`6080` 只綁定 `127.0.0.1`。若設定 `HERMES_GUI_BIND_ADDRESS=0.0.0.0`，桌面會出現在主機所有介面上，而唯一的防線只有一組 8 字元的 VNC 密碼；僅在受信任的網路這麼做。
2. **務必修改預設密碼**：`VNC_PASSWORD` 與 Dashboard 的 `HERMES_DASHBOARD_BASIC_AUTH_PASSWORD`。
3. **Dashboard 對外服務時**請設定 Basic Auth，並建議設定 `HERMES_DASHBOARD_BASIC_AUTH_SECRET`（可用 `openssl rand -hex 32` 產生）以維持 session 穩定。
4. **VNC 密碼僅在首次啟動寫入** `data/.vnc/passwd` 與 `data/.config/tigervnc/passwd`。若要變更，刪除這兩個檔案後修改 `.env` 中的 `VNC_PASSWORD` 再重啟容器。

## 疑難排解

### noVNC 黑畫面或連不上

```bash
docker compose logs gateway
docker compose exec gateway /docker/gui/hermes-vnc-restart.sh
```

確認 port `6080` 未被其他程式佔用。

### `./data` 權限錯誤

確認 `.env` 的 `HERMES_UID` / `HERMES_GID` 與主機使用者一致後，重新執行 setup 或調整目錄擁有者：

```bash
sudo chown -R "$(id -u):$(id -g)" ./data
```

### Windows 上腳本換行問題

專案透過 `.gitattributes` 與 `Dockerfile.gui` 建置時的 CRLF stripping，確保 shell / s6 腳本在 Linux 容器內可正常執行。若在 Windows 直接編輯 `docker/gui/` 下的腳本，請確認儲存為 LF 換行。

### 連接主機上的服務（如 Ollama）

容器已設定 `host.docker.internal:host-gateway`，Agent 可透過 `http://host.docker.internal:<port>` 存取主機服務。

### 更新上游 Hermes Agent

```bash
docker compose build --pull gateway
docker compose up -d
```

## 授權

本專案為 Hermes Agent 的容器化封裝；Hermes Agent 本身請參考 [Nous Research](https://github.com/NousResearch/hermes-agent) 上游專案之授權條款。
