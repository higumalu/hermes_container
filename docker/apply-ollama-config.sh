#!/bin/bash
# 依 .env 的 OLLAMA_* 變數寫入 /opt/data/config.yaml（local Ollama OpenAI API）
set -euo pipefail

OLLAMA_BASE_URL="${OLLAMA_BASE_URL:-}"
OLLAMA_MODEL="${OLLAMA_MODEL:-}"
OLLAMA_AUTO_CONFIG="${OLLAMA_AUTO_CONFIG:-1}"

[ -n "${OLLAMA_BASE_URL}" ] || exit 0
[ "${OLLAMA_AUTO_CONFIG}" = "1" ] || exit 0
[ -f /opt/data/config.yaml ] || exit 0

OLLAMA_MODEL="${OLLAMA_MODEL:-llama3.2}"
OLLAMA_CONTEXT_LENGTH="${OLLAMA_CONTEXT_LENGTH:-65536}"

# 確保 URL 以 /v1 結尾（Hermes custom endpoint 格式）
case "${OLLAMA_BASE_URL}" in
  */v1) ;;
  */v1/) OLLAMA_BASE_URL="${OLLAMA_BASE_URL%/}" ;;
  *) OLLAMA_BASE_URL="${OLLAMA_BASE_URL%/}/v1" ;;
esac

echo "[ollama] 設定 Hermes → ${OLLAMA_BASE_URL}  model=${OLLAMA_MODEL}"

export OLLAMA_BASE_URL OLLAMA_MODEL OLLAMA_CONTEXT_LENGTH
export OLLAMA_API_KEY="${OLLAMA_API_KEY:-}"

/opt/hermes/venv/bin/python3 <<PY
import os
from pathlib import Path

try:
    import yaml
except ImportError:
    raise SystemExit("PyYAML not available")

path = Path("/opt/data/config.yaml")
data = yaml.safe_load(path.read_text()) or {}
model = data.setdefault("model", {})
model["provider"] = "custom"
model["default"] = os.environ["OLLAMA_MODEL"]
model["base_url"] = os.environ["OLLAMA_BASE_URL"]
model["api_key"] = os.environ.get("OLLAMA_API_KEY", "") or ""
if os.environ.get("OLLAMA_CONTEXT_LENGTH"):
    model["context_length"] = int(os.environ["OLLAMA_CONTEXT_LENGTH"])

# 具名 provider，方便 /model custom:ollama:xxx
providers = data.setdefault("providers", {})
providers["ollama"] = {
    "provider": "custom",
    "base_url": os.environ["OLLAMA_BASE_URL"],
    "default": os.environ["OLLAMA_MODEL"],
    "api_key": "",
}

path.write_text(yaml.dump(data, default_flow_style=False, allow_unicode=True, sort_keys=False))
print("[ollama] config.yaml 已更新")
PY

# 權限（非 root 模式）
if [ "$(id -u)" -eq 0 ] && id hermes &>/dev/null; then
  chown hermes:hermes /opt/data/config.yaml 2>/dev/null || true
fi
