# SearXNG 搜尋整合

Hermes 內建 **web-searxng** 外掛，透過環境變數 `SEARXNG_URL` 與 `config.yaml` 的 `web.search_backend: searxng` 啟用。

## 快速啟動

### 1. `.env` 加入

```bash
SEARXNG_URL=http://searxng:8080
SEARXNG_AUTO_CONFIG=1
```

### 2. 啟動 SearXNG + Hermes

```bash
docker compose --profile searxng up -d --force-recreate
```

（若只要 SearXNG、Hermes 已在跑：`docker compose --profile searxng up -d` 後重啟 gateway）

### 3. 驗證

```bash
# SearXNG API
curl -s "http://127.0.0.1:8080/search?q=test&format=json" | head -c 200

# 從 Hermes 容器內
docker exec hermes curl -s "http://searxng:8080/search?q=hermes&format=json" | head -c 200

# Hermes 設定
docker exec hermes grep -E "SEARXNG|search_backend" /opt/data/.env /opt/data/config.yaml
```

Agent 使用 `web_search` 工具時會走 SearXNG。

---

## 與 Ollama 一起啟動

```bash
docker compose --profile ollama --profile searxng up -d
```

`.env` 範例：

```bash
OLLAMA_BASE_URL=http://ollama:11434/v1
OLLAMA_MODEL=llama3.2
SEARXNG_URL=http://searxng:8080
```

---

## 設定檔

| 路徑 | 說明 |
|------|------|
| `searxng/settings.yml` | SearXNG 設定（已啟用 `json` 格式、`limiter: false`） |
| `./data/.env` | 自動寫入 `SEARXNG_URL=...` |
| `./data/config.yaml` | 自動設 `web.search_backend: searxng` |

生產環境請修改 `searxng/settings.yml` 的 `server.secret_key`。

---

## 手動設定

設 `SEARXNG_AUTO_CONFIG=0`，手動編輯：

```yaml
# ./data/config.yaml
web:
  search_backend: searxng
```

```bash
# ./data/.env
SEARXNG_URL=http://searxng:8080
```

或執行 `hermes tools` / `hermes setup` 選擇 SearXNG。

---

## 常見問題

| 問題 | 處理 |
|------|------|
| Connection refused | 確認 `--profile searxng` 已啟動；URL 用 `http://searxng:8080` 非 localhost |
| 403 / rate limit | `settings.yml` 已設 `limiter: false` |
| 搜尋仍走 DuckDuckGo | 確認 `web.search_backend: searxng` 與 `SEARXNG_URL` 已寫入並重啟 gateway |
