#!/bin/bash
# 建立 hermes 使用者；若目標 UID/GID 已被佔用（Ubuntu 映像常見 uid 1000），先挪開再建立。
set -euo pipefail

HERMES_UID="${HERMES_UID:-10000}"
HERMES_GID="${HERMES_GID:-10000}"

free_uid() {
  local uid="$1"
  local entry name
  entry="$(getent passwd "${uid}" || true)"
  [ -z "${entry}" ] && return 0
  name="$(echo "${entry}" | cut -d: -f1)"
  [ "${name}" = "hermes" ] && return 0
  # 挪到不衝突的 UID（遞增直到可用）
  local new_uid=19999
  while getent passwd "${new_uid}" >/dev/null 2>&1; do
    new_uid=$((new_uid + 1))
  done
  usermod -u "${new_uid}" "${name}"
}

free_gid() {
  local gid="$1"
  local entry name
  entry="$(getent group "${gid}" || true)"
  [ -z "${entry}" ] && return 0
  name="$(echo "${entry}" | cut -d: -f1)"
  [ "${name}" = "hermes" ] && return 0
  local new_gid=19999
  while getent group "${new_gid}" >/dev/null 2>&1; do
    new_gid=$((new_gid + 1))
  done
  groupmod -g "${new_gid}" "${name}"
}

free_uid "${HERMES_UID}"
free_gid "${HERMES_GID}"

if getent group hermes >/dev/null 2>&1; then
  groupmod -g "${HERMES_GID}" hermes
else
  groupadd -g "${HERMES_GID}" hermes
fi

if getent passwd hermes >/dev/null 2>&1; then
  usermod -u "${HERMES_UID}" -g hermes -d /opt/data -s /bin/bash hermes
else
  useradd -u "${HERMES_UID}" -g hermes -m -d /opt/data -s /bin/bash hermes
fi

mkdir -p /opt/data
chown -R hermes:hermes /opt/data
