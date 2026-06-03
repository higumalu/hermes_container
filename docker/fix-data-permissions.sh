#!/bin/bash
# 修正 /opt/data 內被 root 建立的檔案（setup、docker exec 常見）
set -euo pipefail

TARGET_USER="${HERMES_FIX_USER:-hermes}"
TARGET_GROUP="${HERMES_FIX_GROUP:-hermes}"

if ! id "${TARGET_USER}" &>/dev/null; then
  exit 0
fi

# 僅處理 root 擁有的檔案，避免每次全量 chown
while IFS= read -r -d '' path; do
  chown "${TARGET_USER}:${TARGET_GROUP}" "${path}" 2>/dev/null || true
done < <(find /opt/data -xdev \( -user root -o -group root \) -print0 2>/dev/null)

# 敏感檔權限
[ -f /opt/data/.env ] && chmod 600 /opt/data/.env
[ -d /opt/data/.vnc ] && chmod 700 /opt/data/.vnc
