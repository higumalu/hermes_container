# Hermes Agent — 自訂 Ubuntu + GUI 映像
# 基於 Ubuntu，安裝 XFCE + TigerVNC + noVNC，並透過官方 install.sh 安裝 Hermes
#
# 建置：
#   docker compose build
#   docker compose build --build-arg HERMES_BRANCH=main

ARG UBUNTU_VERSION=24.04
FROM ubuntu:${UBUNTU_VERSION}

LABEL org.opencontainers.image.title="Hermes Agent (Ubuntu + GUI)"
LABEL org.opencontainers.image.source="https://github.com/NousResearch/hermes-agent"

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    HERMES_HOME=/opt/data \
    PLAYWRIGHT_BROWSERS_PATH=/opt/hermes/.playwright \
    DISPLAY=:1 \
  # noVNC / VNC
    VNC_DISPLAY=:1 \
    VNC_PORT=5901 \
    NOVNC_PORT=6080 \
    VNC_RESOLUTION=1920x1080

# ---------- 系統套件：GUI 桌面 + Hermes 相依 ----------
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl git sudo wget \
    # XFCE 桌面 + VNC + 瀏覽器存取 noVNC
    xfce4 xfce4-terminal dbus dbus-x11 \
    tigervnc-standalone-server tigervnc-common tigervnc-tools \
    novnc websockify \
    # Hermes / Playwright 常用相依
    python3 python3-venv python-is-python3 \
    ripgrep ffmpeg gcc python3-dev libffi-dev \
    openssh-client xz-utils procps \
    # 字型（避免中文/介面方塊字）
    fonts-dejavu fonts-noto-cjk \
    # Google Chrome 相依
    gnupg \
    && rm -rf /var/lib/apt/lists/*

# ---------- Google Chrome（amd64；ARM 請改用 Chromium 或自行調整） ----------
RUN set -eux; \
    arch="$(dpkg --print-architecture)"; \
    if [ "$arch" = "amd64" ]; then \
      curl -fsSL https://dl.google.com/linux/linux_signing_key.pub \
        | gpg --dearmor -o /usr/share/keyrings/google-chrome.gpg; \
      echo "deb [arch=amd64 signed-by=/usr/share/keyrings/google-chrome.gpg] https://dl.google.com/linux/chrome/deb/ stable main" \
        > /etc/apt/sources.list.d/google-chrome.list; \
      apt-get update; \
      apt-get install -y --no-install-recommends google-chrome-stable; \
      rm -rf /var/lib/apt/lists/*; \
    else \
      echo "WARN: Google Chrome 僅提供 amd64，此架構 ($arch) 改裝 Chromium" >&2; \
      sed -i '/^Components:/ s/ main$/ main universe/' /etc/apt/sources.list.d/ubuntu.sources 2>/dev/null \
        || sed -i 's/ main restricted/ main restricted universe/' /etc/apt/sources.list 2>/dev/null || true; \
      apt-get update; \
      apt-get install -y --no-install-recommends chromium; \
      chromium_bin="$(command -v chromium || command -v chromium-browser)"; \
      ln -sf "${chromium_bin}" /usr/bin/google-chrome-stable; \
      rm -rf /var/lib/apt/lists/*; \
    fi

COPY docker/chrome-wrapper.sh /usr/local/bin/chrome
RUN chmod +x /usr/local/bin/chrome \
    && ln -sf /usr/local/bin/chrome /usr/local/bin/google-chrome

# Playwright / Hermes 瀏覽器工具可指向系統 Chrome
ENV CHROME_EXECUTABLE=/usr/local/bin/chrome \
    PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH=/usr/bin/google-chrome-stable

# ---------- 建立 hermes 使用者（build-arg 可設為 host 的 id -u / id -g） ----------
ARG HERMES_UID=10000
ARG HERMES_GID=10000
COPY docker/create-hermes-user.sh /usr/local/bin/create-hermes-user.sh
RUN chmod +x /usr/local/bin/create-hermes-user.sh \
    && HERMES_UID="${HERMES_UID}" HERMES_GID="${HERMES_GID}" /usr/local/bin/create-hermes-user.sh

# ---------- 安裝 Hermes Agent ----------
ARG HERMES_BRANCH=main
ARG HERMES_COMMIT=
ARG SKIP_BROWSER=0
COPY docker/install-hermes.sh /usr/local/bin/install-hermes.sh
RUN chmod +x /usr/local/bin/install-hermes.sh \
    && HERMES_BRANCH="${HERMES_BRANCH}" \
       HERMES_COMMIT="${HERMES_COMMIT}" \
       SKIP_BROWSER="${SKIP_BROWSER}" \
       /usr/local/bin/install-hermes.sh

ENV PATH="/opt/hermes/venv/bin:/opt/data/.local/bin:${PATH}"

# ---------- VNC 設定（模板在 /opt/.vnc；執行時複製到 volume /opt/data/.vnc） ----------
ARG VNC_PASSWORD=hermes
COPY docker/vnc-xstartup /opt/.vnc/xstartup
COPY docker/google-chrome.desktop /usr/share/applications/google-chrome.desktop
RUN mkdir -p /opt/.vnc \
    && echo "${VNC_PASSWORD}" | vncpasswd -f > /opt/.vnc/passwd \
    && chmod 700 /opt/.vnc \
    && chmod 600 /opt/.vnc/passwd \
    && chmod +x /opt/.vnc/xstartup \
    && chown -R hermes:hermes /opt/.vnc

COPY docker/entrypoint.sh /usr/local/bin/hermes-entrypoint.sh
COPY docker/seed-hermes-data.sh /usr/local/bin/seed-hermes-data.sh
COPY docker/fix-data-permissions.sh /usr/local/bin/fix-data-permissions.sh
COPY docker/apply-ollama-config.sh /usr/local/bin/apply-ollama-config.sh
COPY docker/apply-searxng-config.sh /usr/local/bin/apply-searxng-config.sh
COPY docker/hermes-shim.sh /usr/local/bin/hermes
COPY docker/hermes-chat.desktop docker/hermes-setup.desktop /usr/share/applications/
RUN mkdir -p /etc/hermes/seed/Desktop \
    && cp /usr/share/applications/hermes-chat.desktop /usr/share/applications/hermes-setup.desktop /etc/hermes/seed/Desktop/
RUN chmod +x /usr/local/bin/hermes-entrypoint.sh \
    /usr/local/bin/seed-hermes-data.sh \
    /usr/local/bin/fix-data-permissions.sh \
    /usr/local/bin/apply-ollama-config.sh \
    /usr/local/bin/apply-searxng-config.sh \
    /usr/local/bin/hermes

WORKDIR /opt/hermes
VOLUME ["/opt/data"]

# VNC | noVNC | Gateway API | Dashboard
EXPOSE 5901 6080 8642 9119

ENTRYPOINT ["/usr/local/bin/hermes-entrypoint.sh"]
# gateway = 啟動 GUI + Hermes gateway；setup = 設定精靈；其他 = hermes 子命令
CMD ["gateway"]
