#!/bin/bash
# YouTube Music リモートデスクトップ 正常停止スクリプト

set -e
cd "$(dirname "$0")"

echo "=== [1/2] Firefox を正常終了させています... ==="
podman exec -i yt_music_kiosk python3 - << 'PYEOF'
import sys, time, subprocess

# ─── 1. Firefox を SIGTERM で終了させる ──────────────────────────────────────
r = subprocess.run(['pkill', '-SIGTERM', '-f', 'firefox'], capture_output=True)
if r.returncode == 0:
    print("[stop] Firefox に SIGTERM を送信しました")
else:
    print("[stop] Firefox プロセスが見つかりません (既に終了済みか起動中)")

# ─── 2. Firefox プロセスが終了するまで待つ ───────────────────────────────────
print("[stop] Firefox の終了を待機中...")
for _ in range(30):  # 最大 15 秒待つ
    r = subprocess.run(['pgrep', '-f', 'firefox'], capture_output=True)
    if r.returncode != 0:
        print("[stop] Firefox が終了しました")
        break
    time.sleep(0.5)
else:
    print("[stop] タイムアウト: Firefox がまだ動作中 (強制終了します)")
    subprocess.run(['pkill', '-SIGKILL', '-f', 'firefox'], capture_output=True)
PYEOF

echo "=== [2/2] コンテナを停止しています... ==="
podman-compose down

echo ""
echo "=========================================="
echo " 正常停止完了"
echo "=========================================="
