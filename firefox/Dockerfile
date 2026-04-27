FROM lscr.io/linuxserver/firefox:latest
# rootless Podman では PID 1 が UID 1000 として動作するため、
# setuid バイナリ lsiown を誰でも実行できるようにパーミッションを修正
RUN chmod o+x /usr/bin/lsiown

RUN apt-get update \
    && apt-get install -y --no-install-recommends playerctl curl \
    && rm -rf /var/lib/apt/lists/*

# YouTube Music アイコンをビルド時に取得
# 起動時のネットワーク依存をなくするため Dockerfile で実行。
# /usr/local/share は Selkies の初期化でリセットされない安全な場所。
# 起動時に init スクリプトが Selkies web ディレクトリにコピーする。
RUN curl -sL https://music.youtube.com/img/favicon_144.png \
    -o /usr/local/share/ytm-icon.png || true
