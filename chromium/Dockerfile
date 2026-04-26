FROM lscr.io/linuxserver/chromium:latest
# rootless Podman では PID 1 が UID 1000 として動作するため、
# setuid バイナリ lsiown を誰でも実行できるようにパーミッションを修正
RUN chmod o+x /usr/bin/lsiown

RUN apt-get update \
    && apt-get install -y --no-install-recommends playerctl \
    && rm -rf /var/lib/apt/lists/*
RUN /lsiopy/bin/pip3 install websocket-client
