#!/bin/bash
# 依 .env 設定 Hermes 使用 SearXNG 搜尋
set -euo pipefail

SEARXNG_URL="${SEARXNG_URL:-}"
SEARXNG_AUTO_CONFIG="${SEARXNG_AUTO_CONFIG:-1}"

[ -n "${SEARXNG_URL}" ] || exit 0
[ "${SEARXNG_AUTO_CONFIG}" = "1" ] || exit 0

SEARXNG_URL="${SEARXNG_URL%/}"

echo "[searxng] 設定 Hermes 搜尋 → ${SEARXNG_URL}"

# 寫入 /opt/data/.env（Hermes 讀 HERMES_HOME/.env）
ENV_FILE="/opt/data/.env"
touch "${ENV_FILE}"
if grep -q '^SEARXNG_URL=' "${ENV_FILE}" 2>/dev/null; then
  sed -i "s|^SEARXNG_URL=.*|SEARXNG_URL=${SEARXNG_URL}|" "${ENV_FILE}"
else
  printf '\n# SearXNG（Compose 內建或自架）\nSEARXNG_URL=%s\n' "${SEARXNG_URL}" >> "${ENV_FILE}"
fi

if [ -f /opt/data/config.yaml ]; then
  export SEARXNG_URL
  /opt/hermes/venv/bin/python3 <<'PY'
import os
from pathlib import Path
import yaml

path = Path("/opt/data/config.yaml")
data = yaml.safe_load(path.read_text()) or {}
web = data.setdefault("web", {})
web["search_backend"] = "searxng"
if not web.get("backend"):
    web["backend"] = "searxng"
path.write_text(yaml.dump(data, default_flow_style=False, allow_unicode=True, sort_keys=False))
print("[searxng] config.yaml web.search_backend=searxng")
PY
fi

if [ "$(id -u)" -eq 0 ] && id hermes &>/dev/null; then
  chown hermes:hermes "${ENV_FILE}" /opt/data/config.yaml 2>/dev/null || true
fi
