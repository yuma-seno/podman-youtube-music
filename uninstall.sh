#!/bin/bash
# YouTube Music Podman Service アンインストールスクリプト

set -e
SERVICE_NAME="podman-youtube-music"
SERVICE_FILE="${SERVICE_NAME}.service"
SYSTEMD_USER_DIR="${HOME}/.config/systemd/user"

echo "=== YouTube Music Podman Service アンインストーラー ==="
echo ""

# ── サービス停止・無効化 ───────────────────────────────────────────────────────
if systemctl --user is-active "${SERVICE_NAME}.service" &>/dev/null; then
    echo "[1/3] サービスを停止しています (Chrome を正常終了させます)..."
    systemctl --user stop "${SERVICE_NAME}.service"
else
    echo "[1/3] サービスはすでに停止しています。"
fi

if systemctl --user is-enabled "${SERVICE_NAME}.service" &>/dev/null; then
    echo "[2/3] サービスの自動起動を無効化しています..."
    systemctl --user disable "${SERVICE_NAME}.service"
else
    echo "[2/3] サービスはすでに無効化されています。"
fi

# ── サービスファイルの削除 ────────────────────────────────────────────────────
echo "[3/3] サービスファイルを削除しています..."
rm -f "${SYSTEMD_USER_DIR}/${SERVICE_FILE}"
systemctl --user daemon-reload

echo ""
echo "=========================================="
echo " アンインストール完了"
echo ""
echo " ⚠  コンテナデータ (./config/) は削除されていません。"
echo "    完全に削除する場合は以下を実行してください:"
echo "    podman-compose down -v   # ボリュームも削除"
echo "    rm -rf ./config/         # プロファイルデータ削除"
echo "=========================================="
