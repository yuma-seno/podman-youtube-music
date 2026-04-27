#!/bin/bash
# YouTube Music Podman Service インストールスクリプト

set -e
INSTALL_DIR="$(cd "$(dirname "$0")" && pwd)"
SERVICE_NAME="podman-youtube-music"
SERVICE_FILE="${SERVICE_NAME}.service"
SYSTEMD_USER_DIR="${HOME}/.config/systemd/user"

echo "=== YouTube Music Podman Service インストーラー ==="
echo "インストール先: ${INSTALL_DIR}"
echo ""

# ── 前提チェック ──────────────────────────────────────────────────────────────
if ! command -v podman &>/dev/null; then
    echo "❌ podman が見つかりません。インストールしてください。"
    exit 1
fi
if ! command -v podman-compose &>/dev/null; then
    echo "❌ podman-compose が見つかりません。インストールしてください。"
    exit 1
fi
if ! systemctl --user status &>/dev/null; then
    echo "❌ systemd ユーザーセッションが利用できません。"
    exit 1
fi
if [[ ! -f "${INSTALL_DIR}/.env" ]]; then
    echo "⚠  .env ファイルが見つかりません。"
    echo "   cp ${INSTALL_DIR}/.env.example ${INSTALL_DIR}/.env"
    echo "   を実行して DOMAIN / DUCKDNS_TOKEN / ACME_EMAIL を設定してください。"
    exit 1
fi

# ── systemd サービスのインストール ────────────────────────────────────────────
echo "[1/3] systemd ユーザーサービスを生成・インストールします..."
mkdir -p "${SYSTEMD_USER_DIR}"

# テンプレートの @INSTALL_DIR@ を実際のパスに置換して生成
sed "s|@INSTALL_DIR@|${INSTALL_DIR}|g" \
    "${INSTALL_DIR}/${SERVICE_FILE}" \
    > "${SYSTEMD_USER_DIR}/${SERVICE_FILE}"

echo "      → ${SYSTEMD_USER_DIR}/${SERVICE_FILE}"

# ── systemd 有効化 ────────────────────────────────────────────────────────────
echo "[2/3] systemd サービスを有効化します..."
systemctl --user daemon-reload
systemctl --user enable "${SERVICE_NAME}.service"

# ── ~/.profile / ~/.bashrc の既存の自動起動設定を確認 ─────────────────────────
echo "[3/3] 既存の自動起動設定を確認します..."
PROFILE_FILES=("${HOME}/.profile" "${HOME}/.bashrc" "${HOME}/.bash_profile")
FOUND=0
for f in "${PROFILE_FILES[@]}"; do
    # コメント行を除いて検索（#で始まる行はスキップ）
    if [[ -f "$f" ]] && grep -v '^\s*#' "$f" 2>/dev/null | grep -q "start\.sh\|yt_music_kiosk\|youtube-music"; then
        echo "   ⚠  ${f} に自動起動の記述が見つかりました。"
        echo "      systemd サービスと重複するため、手動で削除してください。"
        FOUND=1
    fi
done
if [[ $FOUND -eq 0 ]]; then
    echo "   ✓ 重複する自動起動設定は見つかりませんでした。"
fi

echo ""
echo "=========================================="
echo " インストール完了！"
echo ""
echo " 次回 PC 起動時から自動的にコンテナが起動します。"
echo ""
echo " 操作方法:"
echo "   起動:   systemctl --user start  ${SERVICE_NAME}"
echo "   停止:   systemctl --user stop   ${SERVICE_NAME}"
echo "   再起動: systemctl --user restart ${SERVICE_NAME}"
echo "   状態:   systemctl --user status  ${SERVICE_NAME}"
echo ""
echo " ※ ログアウト後もコンテナを動かし続けたい場合（サーバー用途）:"
echo "   loginctl enable-linger"
echo "=========================================="
