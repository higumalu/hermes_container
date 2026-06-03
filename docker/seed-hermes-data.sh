#!/bin/bash
# 首次啟動時，從映像種子目錄還原 Hermes 設定到 volume（./data）
set -euo pipefail

SEED_DIR="${HERMES_SEED_DIR:-/etc/hermes/seed}"

seed_if_missing() {
  local name="$1"
  if [ ! -e "/opt/data/${name}" ] && [ -e "${SEED_DIR}/${name}" ]; then
    cp -a "${SEED_DIR}/${name}" "/opt/data/${name}"
    echo "[seed] restored /opt/data/${name}"
  fi
}

if [ ! -d "${SEED_DIR}" ]; then
  exit 0
fi

mkdir -p /opt/data

for item in .env config.yaml SOUL.md .install_method; do
  seed_if_missing "${item}"
done

# 常用子目錄
for dir in cron hooks skills memories sessions logs; do
  if [ ! -d "/opt/data/${dir}" ] && [ -d "${SEED_DIR}/${dir}" ]; then
    cp -a "${SEED_DIR}/${dir}" "/opt/data/${dir}"
    echo "[seed] restored /opt/data/${dir}/"
  fi
done

# shell PATH（VNC 終端機可執行 hermes）
if ! grep -q 'HERMES_HOME=/opt/data' /opt/data/.bashrc 2>/dev/null; then
  cat >> /opt/data/.bashrc <<'EOF'

# Hermes Agent
export HOME=/opt/data
export HERMES_HOME=/opt/data
export PATH="/opt/hermes/venv/bin:/opt/data/.local/bin:$PATH"
EOF
  echo "[seed] updated /opt/data/.bashrc"
fi

if ! grep -q 'HERMES_HOME=/opt/data' /opt/data/.profile 2>/dev/null; then
  cat >> /opt/data/.profile <<'EOF'

# Hermes Agent
export HOME=/opt/data
export HERMES_HOME=/opt/data
export PATH="/opt/hermes/venv/bin:/opt/data/.local/bin:$PATH"
EOF
  echo "[seed] updated /opt/data/.profile"
fi

# 桌面捷徑
if [ -d "${SEED_DIR}/Desktop" ]; then
  mkdir -p /opt/data/Desktop
  cp -n "${SEED_DIR}/Desktop/"* /opt/data/Desktop/ 2>/dev/null || true
fi

chown -R hermes:hermes /opt/data 2>/dev/null || true
/usr/local/bin/fix-data-permissions.sh 2>/dev/null || true
