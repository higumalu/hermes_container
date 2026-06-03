#!/bin/bash
# root 執行 hermes 時自動降權為 hermes，避免寫出 root:root 的 .env / config.yaml
if [ "$(id -u)" -eq 0 ] && [ "${HERMES_DOCKER_EXEC_AS_ROOT:-0}" != "1" ]; then
  export HERMES_HOME="${HERMES_HOME:-/opt/data}"
  exec su - hermes -c "
    export HOME=/opt/data
    export HERMES_HOME=/opt/data
    export DISPLAY=${DISPLAY:-:1}
    export PATH=/opt/hermes/venv/bin:/opt/data/.local/bin:\$PATH
    exec /opt/hermes/venv/bin/hermes $(printf '%q ' "$@")
  "
fi
exec /opt/hermes/venv/bin/hermes "$@"
