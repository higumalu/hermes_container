#!/command/with-contenv bash
# with-contenv is required: s6-overlay runs /etc/cont-init.d scripts without the
# container environment otherwise, so VNC_PASSWORD and friends arrive empty.
set -euo pipefail

HERMES_HOME="${HERMES_HOME:-/opt/data}"
VNC_DIR="${HERMES_HOME}/.vnc"
TIGERVNC_DIR="${HERMES_HOME}/.config/tigervnc"

mkdir -p "${VNC_DIR}" "${TIGERVNC_DIR}"
chmod 700 "${VNC_DIR}" "${HERMES_HOME}/.config" "${TIGERVNC_DIR}"

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

if [ -n "${VNC_PASSWORD:-}" ]; then
  if [ "${#VNC_PASSWORD}" -gt 8 ]; then
    echo "cont-init-vnc: note - the VNC protocol only uses the first 8 characters of VNC_PASSWORD." >&2
  fi
  for passwd_file in "${TIGERVNC_DIR}/passwd" "${VNC_DIR}/passwd"; do
    if [ ! -f "${passwd_file}" ]; then
      echo "${VNC_PASSWORD}" | vncpasswd -f > "${passwd_file}"
      chmod 600 "${passwd_file}"
    fi
  done
elif [ ! -f "${TIGERVNC_DIR}/passwd" ] && [ ! -f "${VNC_DIR}/passwd" ]; then
  # vncserver prompts for a password it can never read, exits 1, and s6 would
  # restart gui-stack forever with only a black noVNC screen to show for it.
  echo "cont-init-vnc: VNC_PASSWORD is empty and no password file exists." >&2
  echo "cont-init-vnc: vncserver cannot start without one. Set VNC_PASSWORD in .env and restart." >&2
  exit 1
fi

if id hermes >/dev/null 2>&1; then
  chown -R hermes:hermes "${VNC_DIR}" "${HERMES_HOME}/.config" || true
fi
