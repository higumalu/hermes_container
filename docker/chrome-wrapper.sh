#!/bin/sh
# 容器 / VNC 環境下啟動 Google Chrome
exec /usr/bin/google-chrome-stable \
  --no-sandbox \
  --disable-dev-shm-usage \
  --disable-gpu \
  "$@"
