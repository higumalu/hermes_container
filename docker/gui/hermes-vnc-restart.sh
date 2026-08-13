#!/bin/bash
# Manual VNC stack restart (debug). Normally s6 gui-stack handles this on boot.
set -euo pipefail

HERMES_HOME="${HERMES_HOME:-/opt/data}"
VNC_DISPLAY="${VNC_DISPLAY:-:1}"
VNC_PORT="${VNC_PORT:-5901}"

s6-svc -d /run/service/gui-stack 2>/dev/null || true
sleep 1
s6-setuidgid hermes vncserver -kill "${VNC_DISPLAY}" 2>/dev/null || true
pkill -f "websockify.*${VNC_PORT}" 2>/dev/null || true
s6-svc -u /run/service/gui-stack

echo "GUI stack restarted. noVNC: http://localhost:${NOVNC_WS_PORT:-6080}/vnc_lite.html"
