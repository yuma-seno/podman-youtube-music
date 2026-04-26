#!/bin/bash
# YouTube Music リモートデスクトップ 起動スクリプト

set -e
cd "$(dirname "$0")"

PROJECT="podman-youtube-music"
NETWORK="${PROJECT}_default"
AARDVARK_FILE="/run/user/1000/containers/networks/aardvark-dns/$NETWORK"

export HOST_UID=$(id -u)
export HOST_GID=$(id -g)
echo "=== [0/4] 実行ユーザー確認 (UID: $HOST_UID, GID: $HOST_GID) ==="

echo "=== [1/4] コンテナ停止・削除 ==="
podman stop yt_music_kiosk yt_caddy 2>/dev/null || true
podman rm   yt_music_kiosk yt_caddy 2>/dev/null || true

echo "=== [2/4] ネットワーク削除 (aardvark-dns リセット) ==="
podman network rm "$NETWORK" 2>/dev/null || true
rm -f "$AARDVARK_FILE"

echo "=== [3/4] 残留ロックファイルの掃除 ==="
# ⚠️ 権限(chmod/chown)は絶対にいじらない！コンテナの起動を邪魔するゴミファイル「だけ」を消す
CONFIG_ABS="$(cd "$(dirname "$0")" && realpath ./config)"

# X11 / VNC のランタイムゴミを削除
rm -f "${CONFIG_ABS}"/.X*-lock 2>/dev/null || true
rm -f "${CONFIG_ABS}"/.Xauthority 2>/dev/null || true
rm -rf "${CONFIG_ABS}"/.X11-unix 2>/dev/null || true
rm -f "${CONFIG_ABS}"/.vnc/*.pid 2>/dev/null || true
rm -f "${CONFIG_ABS}"/.vnc/*.sock 2>/dev/null || true

# Chromeのクラッシュロックを削除
rm -f "${CONFIG_ABS}"/.config/chromium/Singleton* 2>/dev/null || true

echo "=== [4/4] コンテナ起動 ==="
podman-compose up -d

DOMAIN=$(grep DOMAIN .env | cut -d= -f2)
echo ""
echo "=========================================="
echo " アクセス先: https://${DOMAIN}:8443/"
echo "=========================================="
