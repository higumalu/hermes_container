#!/bin/bash
# Docker 建置階段：安裝 Hermes 到 /opt/hermes（不在 volume），再交給 hermes 使用者
set -euo pipefail

HERMES_BRANCH="${HERMES_BRANCH:-main}"
HERMES_COMMIT="${HERMES_COMMIT:-}"
SKIP_BROWSER="${SKIP_BROWSER:-0}"

mkdir -p /opt/data
chown hermes:hermes /opt/data

curl -fsSL https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh \
  -o /tmp/hermes-install.sh

install_args=(
  --skip-setup
  --non-interactive
  --dir /opt/hermes
  --hermes-home /opt/data
  --branch "${HERMES_BRANCH}"
)

if [ "${SKIP_BROWSER}" = "1" ]; then
  install_args+=(--skip-browser)
fi

if [ -n "${HERMES_COMMIT}" ]; then
  install_args+=(--commit "${HERMES_COMMIT}")
fi

echo ">>> hermes install (root): ${install_args[*]}"
bash /tmp/hermes-install.sh "${install_args[@]}"
rm -f /tmp/hermes-install.sh

# root 安裝的 venv 指向 /root/.local/share/uv，hermes 無法穿越 /root
# → 將 uv 搬到 /opt/uv 並以 hermes 重建 venv
if [ -d /root/.local/share/uv ]; then
  mkdir -p /opt/uv/bin /opt/uv/share
  cp -a /root/.local/bin/uv /root/.local/bin/uvx /opt/uv/bin/ 2>/dev/null || true
  cp -a /root/.local/share/uv /opt/uv/share/
  chown -R hermes:hermes /opt/uv
fi

echo ">>> 以 hermes 使用者重建 venv..."
chown -R hermes:hermes /opt/hermes /opt/uv
rm -rf /opt/hermes/venv
su - hermes -c "
  set -e
  export UV_PYTHON_INSTALL_DIR=/opt/uv/share/uv/python
  export UV_NO_CONFIG=1
  cd /opt/hermes
  /opt/uv/bin/uv venv venv --python 3.11
  /opt/uv/bin/uv pip install --python /opt/hermes/venv/bin/python3 -e '/opt/hermes[all]' --quiet
"

chown -R hermes:hermes /opt/hermes /opt/data

# 保存種子檔到 /etc/hermes/seed（volume 掛載不會覆蓋此目錄）
mkdir -p /etc/hermes/seed/Desktop
for f in .env config.yaml SOUL.md .install_method; do
  [ -e "/opt/data/${f}" ] && cp -a "/opt/data/${f}" "/etc/hermes/seed/${f}"
done
for d in cron hooks skills memories sessions logs; do
  [ -d "/opt/data/${d}" ] && cp -a "/opt/data/${d}" "/etc/hermes/seed/${d}"
done

if ! su - hermes -c '/opt/hermes/venv/bin/hermes --version' >/dev/null 2>&1; then
  echo "ERROR: hermes 使用者無法執行 CLI" >&2
  exit 1
fi

echo ">>> Hermes 安裝完成: $(su - hermes -c '/opt/hermes/venv/bin/hermes --version 2>/dev/null | head -1')"
