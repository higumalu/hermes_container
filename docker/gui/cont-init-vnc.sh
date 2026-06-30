#!/bin/bash
set -euo pipefail

HERMES_HOME="${HERMES_HOME:-/opt/data}"
VNC_DIR="${HERMES_HOME}/.vnc"

mkdir -p "${VNC_DIR}"
chmod 700 "${VNC_DIR}"

if [ ! -f "${VNC_DIR}/xstartup" ]; then
  cp /docker/gui/xstartup.default "${VNC_DIR}/xstartup"
  chmod +x "${VNC_DIR}/xstartup"
elif ! grep -qF "hermes-ibus-chewing" "${VNC_DIR}/xstartup"; then
  sed -i '/^exec startxfce4/i\
# hermes-ibus-chewing\
export GTK_IM_MODULE=ibus\
export QT_IM_MODULE=ibus\
export XMODIFIERS=@im=ibus\
ibus-daemon -drx &\
' "${VNC_DIR}/xstartup"
fi

if [ -n "${VNC_PASSWORD:-}" ] && [ ! -f "${VNC_DIR}/passwd" ]; then
  echo "${VNC_PASSWORD}" | vncpasswd -f > "${VNC_DIR}/passwd"
  chmod 600 "${VNC_DIR}/passwd"
fi

if id hermes >/dev/null 2>&1; then
  chown -R hermes:hermes "${VNC_DIR}" || true
fi
