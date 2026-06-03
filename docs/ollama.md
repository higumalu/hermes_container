# 將 Ollama 接到 Hermes 容器

Hermes 透過 **Custom Endpoint**（OpenAI 相容 API）連本機 Ollama。官方說明：[Providers — Ollama](https://hermes-agent.nousresearch.com/docs/integrations/providers#ollama--local-models-zero-config)

## 方式 A：Ollama 在宿主機（建議）

### 1. 宿主機安裝並啟動 Ollama

```bash
# 安裝後
ollama pull llama3.2          # 或 qwen2.5-coder:32b 等支援 tool 的模型
OLLAMA_CONTEXT_LENGTH=65536 ollama serve
```

> Hermes Agent 建議 **context ≥ 64000**。可用 `ollama ps` 確認 CONTEXT 欄位。

### 2. 設定 `.env`

```bash
OLLAMA_BASE_URL=http://host.docker.internal:11434/v1
OLLAMA_MODEL=llama3.2
OLLAMA_CONTEXT_LENGTH=65536
OLLAMA_AUTO_CONFIG=1
```

`docker-compose.yml` 已含 `extra_hosts: host.docker.internal:host-gateway`（Linux 可用）。

### 3. 重啟 Hermes

```bash
docker compose build
docker compose up -d --force-recreate
```

啟動時會自動更新 `./data/config.yaml` 的 `model` 區段。

### 4. 驗證

```bash
# 從容器內測 Ollama
docker exec hermes curl -s http://host.docker.internal:11434/api/tags | head -c 200

# 測 Hermes
docker exec hermes hermes chat -q "hello" 
```

---

## 方式 B：Ollama 也在 Docker Compose 內

適合不想在宿主機裝 Ollama、或希望網路隔離在同一 compose 專案。

### 1. `.env`

```bash
OLLAMA_BASE_URL=http://ollama:11434/v1
OLLAMA_MODEL=llama3.2
```

### 2. 啟動（含 GPU 時取消 compose 內 nvidia 註解）

```bash
docker compose --profile ollama up -d
docker exec -it ollama ollama pull llama3.2
docker compose up -d --force-recreate gateway
```

### 3. 拉模型

```bash
docker exec -it ollama ollama pull qwen2.5-coder:32b
```

---

## 手動設定（不用自動寫入）

設 `OLLAMA_AUTO_CONFIG=0`，在容器內執行：

```bash
docker exec -it hermes hermes model
# 選 Custom endpoint
# URL: http://host.docker.internal:11434/v1
# API key: 留空
# Model: 與 ollama list 名稱一致
```

或直接編輯 `./data/config.yaml`：

```yaml
model:
  default: llama3.2
  provider: custom
  base_url: http://host.docker.internal:11434/v1
  api_key: ""
  context_length: 65536
```

---

## 常見問題

| 問題 | 處理 |
|------|------|
| Connection refused | 確認宿主機 `ollama serve` 有跑；URL 用 `host.docker.internal` 不是 `localhost` |
| Context too small | 設 `OLLAMA_CONTEXT_LENGTH=65536` 後重啟 ollama |
| Tool calling 失效 | 換支援 function calling 的模型（如 qwen2.5-coder、llama3.1+） |
| 已有其他 API（如 192.168.x） | 那是另一個 gateway；Ollama 預設埠為 **11434** |

## Ollama Cloud（雲端）

與本機不同，需 API Key：`hermes model` → Ollama Cloud，或設 `OLLAMA_API_KEY`（見官方文件）。
