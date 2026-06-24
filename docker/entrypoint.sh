#!/bin/bash
# 啟動順序：VNC (XFCE) → noVNC →（可選）Hermes Gateway
set -uo pipefail

log() { echo "[hermes-entrypoint] $*"; }

is_root_mode() {
  case "${HERMES_RUN_AS_ROOT:-0}" in
    1|true|yes|TRUE|YES) return 0 ;;
    *) return 1 ;;
  esac
}

# 以 hermes 或 root 執行一段 shell（單行）
run_as_agent() {
  local script="$1"
  if is_root_mode; then
    export HOME=/opt/data
    export HERMES_HOME=/opt/data
    export HERMES_ALLOW_ROOT_GATEWAY=1
    export HERMES_DOCKER_EXEC_AS_ROOT=1
    bash -c "${script}"
  else
    su - hermes -c "${script}"
  fi
}

vnc_user() {
  if is_root_mode; then echo "root"; else echo "hermes"; fi
}

# 對齊 volume 擁有者（root 模式略過，避免與 host root 檔案衝突）
if ! is_root_mode && [ -n "${HERMES_UID:-}" ] && [ -n "${HERMES_GID:-}" ]; then
  HERMES_UID="${HERMES_UID}" HERMES_GID="${HERMES_GID}" /usr/local/bin/create-hermes-user.sh
fi

mkdir -p /opt/data /opt/data/.vnc /run/dbus

/usr/local/bin/seed-hermes-data.sh || log "WARN: seed-hermes-data 略過"

if ! is_root_mode; then
  /usr/local/bin/fix-data-permissions.sh || log "WARN: fix-data-permissions 略過"
else
  log "HERMES_RUN_AS_ROOT=1：以 root 執行 Hermes（權限等同 root）"
  export HOME=/opt/data
  export HERMES_HOME=/opt/data
fi

# 若 .env 設了 OLLAMA_BASE_URL，自動寫入 config.yaml
if [ -n "${OLLAMA_BASE_URL:-}" ]; then
  OLLAMA_BASE_URL="${OLLAMA_BASE_URL}" \
  OLLAMA_MODEL="${OLLAMA_MODEL:-}" \
  OLLAMA_API_KEY="${OLLAMA_API_KEY:-}" \
  OLLAMA_CONTEXT_LENGTH="${OLLAMA_CONTEXT_LENGTH:-65536}" \
  OLLAMA_AUTO_CONFIG="${OLLAMA_AUTO_CONFIG:-1}" \
  /usr/local/bin/apply-ollama-config.sh || log "WARN: Ollama 設定略過"
fi

if [ -n "${SEARXNG_URL:-}" ]; then
  SEARXNG_URL="${SEARXNG_URL}" \
  SEARXNG_AUTO_CONFIG="${SEARXNG_AUTO_CONFIG:-1}" \
  /usr/local/bin/apply-searxng-config.sh || log "WARN: SearXNG 設定略過"
fi

seed_vnc_config() {
  mkdir -p /opt/data/.vnc
  for f in passwd xstartup; do
    if [ ! -f "/opt/data/.vnc/${f}" ] && [ -f "/opt/.vnc/${f}" ]; then
      cp -a "/opt/.vnc/${f}" "/opt/data/.vnc/${f}"
    fi
  done
  chmod 700 /opt/data/.vnc
  [ -f /opt/data/.vnc/passwd ] && chmod 600 /opt/data/.vnc/passwd
  [ -f /opt/data/.vnc/xstartup ] && chmod +x /opt/data/.vnc/xstartup
  if ! is_root_mode; then
    chown -R hermes:hermes /opt/data/.vnc
    /usr/local/bin/fix-data-permissions.sh 2>/dev/null || true
  fi
}
seed_vnc_config

start_gui() {
  if [ "${HERMES_GUI_ENABLED:-1}" != "1" ]; then
    log "HERMES_GUI_ENABLED=0，略過 VNC/noVNC"
    return 0
  fi

  local display="${VNC_DISPLAY:-:1}"
  local vnc_port="${VNC_PORT:-5901}"
  local novnc_port="${NOVNC_PORT:-6080}"
  local vnc_display_num="${display#:}"
  local vu
  vu="$(vnc_user)"
  local vnc_list_out=""

  if is_root_mode; then
    export HOME=/opt/data
    vnc_list_out="$(vncserver -list 2>/dev/null || true)"
  else
    vnc_list_out="$(su - hermes -c "vncserver -list" 2>/dev/null || true)"
  fi

  run_vnc() {
  if is_root_mode; then
    export HOME=/opt/data
    vncserver "${display}" \
      -geometry "${VNC_RESOLUTION:-1920x1080}" \
      -depth 24 \
      -rfbport "${vnc_port}" \
      -SecurityTypes VncAuth \
      -passwd /opt/data/.vnc/passwd \
      -xstartup /opt/data/.vnc/xstartup \
      -localhost no
  else
    su - hermes -c "
      vncserver ${display} \
        -geometry ${VNC_RESOLUTION:-1920x1080} \
        -depth 24 \
        -rfbport ${vnc_port} \
        -SecurityTypes VncAuth \
        -passwd /opt/data/.vnc/passwd \
        -xstartup /opt/data/.vnc/xstartup \
        -localhost no
    "
  fi
  }

  if ! echo "${vnc_list_out}" | grep -qE "(^|:)${vnc_display_num}([[:space:]]|$)"; then
    log "啟動 VNC display ${display} (使用者 ${vu}, port ${vnc_port})..."
    if ! run_vnc; then
      log "ERROR: vncserver 啟動失敗"
      cat /opt/data/.vnc/*.log 2>/dev/null || true
      return 1
    fi
  else
    log "VNC display ${display} 已在運行"
  fi

  if ! pgrep -f "websockify.*:${novnc_port}" >/dev/null 2>&1; then
    log "啟動 noVNC → http://0.0.0.0:${novnc_port}/vnc.html"
    websockify --web=/usr/share/novnc/ "0.0.0.0:${novnc_port}" "127.0.0.1:${vnc_port}" &
    WEBSOCKIFY_PID=$!
    sleep 1
  fi

  if curl -sf "http://127.0.0.1:${novnc_port}/vnc.html" >/dev/null 2>&1; then
    log "noVNC 就緒"
  else
    log "WARN: noVNC HTTP 尚未回應"
  fi
}

cleanup() {
  log "關閉中..."
  if is_root_mode; then
    vncserver -kill "${VNC_DISPLAY:-:1}" 2>/dev/null || true
  else
    su - hermes -c "vncserver -kill ${VNC_DISPLAY:-:1}" 2>/dev/null || true
  fi
  pkill -f "websockify.*${NOVNC_PORT:-6080}" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

if ! start_gui; then
  log "GUI 啟動失敗；若只需除錯可設 HERMES_GUI_ENABLED=0"
fi

CMD="${1:-gateway}"
shift || true

hermes_cmd_env='
export HOME=/opt/data
export HERMES_HOME=/opt/data
export DISPLAY='"${VNC_DISPLAY:-:1}"'
export PATH=/opt/hermes/venv/bin:/opt/data/.local/bin:$PATH
export CHROME_EXECUTABLE=/usr/local/bin/chrome
export PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH=/usr/bin/google-chrome-stable
cd /opt/hermes
'
if is_root_mode; then
  hermes_cmd_env="${hermes_cmd_env}export HERMES_ALLOW_ROOT_GATEWAY=1
"
fi

run_gateway() {
  log "啟動 Hermes Gateway（使用者 $(vnc_user)）..."
  run_as_agent "${hermes_cmd_env} exec /opt/hermes/venv/bin/hermes gateway run --no-supervise" &
  echo $! > /tmp/hermes-gateway.pid
}

case "${CMD}" in
  gateway)
    if [ "${HERMES_GATEWAY_ENABLED:-1}" = "1" ]; then
      run_gateway || log "WARN: Gateway 啟動失敗（noVNC 仍可用）"
    fi
    log "容器保持運行 — noVNC: http://<host>:${NOVNC_PORT:-6080}/vnc.html"
    if [ -n "${WEBSOCKIFY_PID:-}" ]; then
      wait "${WEBSOCKIFY_PID}"
    else
      tail -f /dev/null
    fi
    ;;
  setup)
    run_as_agent "${hermes_cmd_env} exec /opt/hermes/venv/bin/hermes setup"
    ;;
  bash|sh)
    if is_root_mode; then
      exec bash
    else
      exec su - hermes
    fi
    ;;
  gui-only)
    log "僅 GUI 模式"
    if [ -n "${WEBSOCKIFY_PID:-}" ]; then
      wait "${WEBSOCKIFY_PID}"
    else
      tail -f /dev/null
    fi
    ;;
  *)
    run_as_agent "${hermes_cmd_env} exec /opt/hermes/venv/bin/hermes ${CMD} $*"
    ;;
esac
