#!/bin/bash
# YouTube Music リモートデスクトップ 起動スクリプト

set -e
cd "$(dirname "$0")"

PROJECT="podman-youtube-music"
NETWORK="${PROJECT}_default"
AARDVARK_FILE="/run/user/$(id -u)/containers/networks/aardvark-dns/$NETWORK"

export HOST_UID=$(id -u)
export HOST_GID=$(id -g)
echo "=== [0/4] 実行ユーザー確認 (UID: $HOST_UID, GID: $HOST_GID) ==="

echo "=== [1/4] コンテナ停止・削除 ==="
echo "  → Firefox を正常終了させています..."
podman exec -i yt_music_kiosk python3 - << 'PYEOF' 2>/dev/null || true
import time, subprocess

subprocess.run(['pkill', '-SIGTERM', '-f', 'firefox'], capture_output=True)
for _ in range(30):
    if subprocess.run(['pgrep', '-f', 'firefox'], capture_output=True).returncode != 0:
        break
    time.sleep(0.5)
PYEOF
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

# Firefoxのプロファイルロックを削除
rm -f "${CONFIG_ABS}"/.mozilla/firefox/*/lock 2>/dev/null || true
rm -f "${CONFIG_ABS}"/.mozilla/firefox/*/.parentlock 2>/dev/null || true

echo "=== [4/4] コンテナ起動 ==="
podman-compose up -d

DOMAIN=$(grep DOMAIN .env | cut -d= -f2)
echo ""
echo "=========================================="
echo " アクセス先: https://${DOMAIN}:8443/"
echo "=========================================="
