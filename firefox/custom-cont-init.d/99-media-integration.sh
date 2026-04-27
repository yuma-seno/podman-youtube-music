#!/bin/bash
# YouTube Music メディア統合サーバー
# Caddy から /media/* でプロキシされ、Windows 通知パネルと連携する

echo "=== メディア統合サーバー セットアップ ==="

# ─── Python サーバー本体 ──────────────────────────────────────────────────────
cat << 'PYEOF' > /usr/local/bin/media-server.py
#!/usr/bin/env python3
"""
YouTube Music リモコンサーバー
"""
import glob
import http.server
import json
import os
import socketserver
import stat
import subprocess
import sys
import time

# ─── HTML ────────────────────────────────────────────────────────────────────
HTML_CONTENT = """\
<!DOCTYPE html>
<html lang="ja">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>YouTube Music リモコン</title>
<link rel="icon" href="data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 100 100'%3E%3Crect x='28' y='8' width='44' height='84' rx='10' fill='%23222'/%3E%3Ccircle cx='50' cy='30' r='9' fill='%23ff4444'/%3E%3Crect x='36' y='52' width='28' height='5' rx='2.5' fill='%23666'/%3E%3Crect x='36' y='63' width='28' height='5' rx='2.5' fill='%23666'/%3E%3Crect x='36' y='74' width='28' height='5' rx='2.5' fill='%23666'/%3E%3C/svg%3E">
<style>
  *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }
  body {
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
    background: #0f0f0f; color: #fff;
    display: flex; flex-direction: column;
    align-items: center; justify-content: center;
    min-height: 100vh; gap: 24px; padding: 24px;
    text-align: center;
  }
  .icon { font-size: 3rem; margin-bottom: -10px; }
  h1 { font-size: 1.2rem; font-weight: 500; color: #ddd; }
  
  /* 初期化ボタン */
  #activate-section { display: flex; flex-direction: column; gap: 16px; align-items: center; }
  .btn {
    padding: 18px 52px; font-size: 1.15rem; font-weight: 700;
    border: none; border-radius: 50px; cursor: pointer;
    background: #f00; color: #fff;
    box-shadow: 0 4px 20px rgba(255,0,0,.4);
    transition: transform .15s, box-shadow .15s, background .2s;
  }
  .btn:hover { transform: translateY(-2px); }
  
  /* プレイヤーコントロール */
  #player-section { 
    display: none; flex-direction: column; align-items: center; gap: 20px;
    background: #1e1e1e; padding: 30px; border-radius: 20px;
    box-shadow: 0 10px 30px rgba(0,0,0,0.5); width: 100%; max-width: 400px;
  }
  #track-title { font-size: 1.3rem; font-weight: bold; color: #fff; line-height: 1.3; }
  #track-artist { font-size: 0.9rem; color: #aaa; margin-top: 4px; }
  .controls { display: flex; gap: 20px; align-items: center; justify-content: center; margin-top: 10px; }
  
  .ctrl-btn {
    background: #333; color: #fff; border: none; border-radius: 50%;
    width: 60px; height: 60px; font-size: 1.5rem;
    display: flex; align-items: center; justify-content: center;
    cursor: pointer; transition: background 0.2s, transform 0.1s;
  }
  .ctrl-btn:hover { background: #444; transform: scale(1.05); }
  .ctrl-btn:active { transform: scale(0.95); }
  
  #toggle-btn { width: 72px; height: 72px; font-size: 2rem; background: #fff; color: #000; }
  #toggle-btn:hover { background: #eee; }

  #status { font-size: .9rem; color: #777; min-height: 1.4em; }
  .hint { font-size: .8rem; color: #555; line-height: 1.6; max-width: 320px; }
</style>
</head>
<body>
<div class="icon">&#127925;</div>
<h1>YouTube Music リモコン</h1>

<div id="activate-section">
  <button class="btn" id="activate-btn">&#9654; 有効化する</button>
  <p class="hint">
    有効化後は<strong>このタブを開いたまま</strong>にしてください<br>
    バックグラウンドで動作し、Win+Aから操作可能になります
  </p>
</div>

<div id="player-section">
  <div style="width: 100%;">
    <div id="track-title">曲名を取得中...</div>
    <div id="track-artist">--</div>
  </div>
  <div class="controls">
    <button class="ctrl-btn" id="prev-btn" title="前の曲">⏮</button>
    <button class="ctrl-btn" id="toggle-btn" title="再生/一時停止">⏯</button>
    <button class="ctrl-btn" id="next-btn" title="次の曲">⏭</button>
  </div>
</div>

<p id="status">接続待機中...</p>

<script>
(function () {
  var activateBtn     = document.getElementById('activate-btn');
  var activateSection = document.getElementById('activate-section');
  var playerSection   = document.getElementById('player-section');
  var statusTxt       = document.getElementById('status');
  
  var trackTitle  = document.getElementById('track-title');
  var trackArtist = document.getElementById('track-artist');
  var prevBtn     = document.getElementById('prev-btn');
  var toggleBtn   = document.getElementById('toggle-btn');
  var nextBtn     = document.getElementById('next-btn');

  var _audio = null;
  var _toggling = false;

  var BASE = (function () {
    var p = location.pathname;
    return p.replace(/\\/?$/, '/');
  })();

  function setStatus(msg) { statusTxt.textContent = msg; }

  async function activate() {
    try {
      var silentWav = "data:audio/wav;base64,UklGRigAAABXQVZFZm10IBAAAAABAAEARKwAAIhYAQACABAAZGF0YQQAAAAAAA==";
      _audio = new Audio(silentWav);
      _audio.loop = true;
      _audio.volume = 0.01;
      await _audio.play();
    } catch (e) {
      setStatus('❌ 音声の再生に失敗: ' + e.message);
      return;
    }

    if (!('mediaSession' in navigator)) {
      setStatus('⚠ このブラウザは Media Session API 非対応です');
      return;
    }

    activateSection.style.display = 'none';
    playerSection.style.display = 'flex';

    navigator.mediaSession.metadata = new MediaMetadata({
      title:  'YouTube Music',
      artist: 'リモコン',
      album:  'Docker Container',
    });

    function applyState(playing) {
      navigator.mediaSession.playbackState = playing ? 'playing' : 'paused';
      toggleBtn.textContent = playing ? '⏸' : '▶';
      setStatus(playing ? '▶ 再生中' : '⏸ 停止中');

      if (_audio) {
        if (playing && _audio.paused) {
          _audio.play().catch(function(e){});
        } else if (!playing && !_audio.paused) {
          _audio.pause();
        }
      }
    }

    // サーバーから状態を取得して反映する関数
    function pollStatus() {
      fetch(BASE + 'status')
        .then(function (r) { return r.json(); })
        .then(function (d) {
          if (d.playing !== null) applyState(d.playing);
          
          // 曲名が有効な場合のみ更新（クリアしない）
          if (d.title && d.title !== "") {
            trackTitle.textContent = d.title;
            trackArtist.textContent = d.artist || 'YouTube Music';

            var cur = navigator.mediaSession.metadata;
            if (!cur || cur.title !== d.title) {
              navigator.mediaSession.metadata = new MediaMetadata({
                title:  d.title,
                artist: d.artist || 'YouTube Music',
                album:  'YouTube Music',
              });
            }
          }
        })
        .catch(function () {});
    }

    // 1秒ごとの定期ポーリング
    setInterval(pollStatus, 1000);

    var doToggle = function () {
      if (_toggling) return;
      _toggling = true;
      var wasPlaying = toggleBtn.textContent === '⏸';
      applyState(!wasPlaying);

      fetch(BASE + 'toggle')
        .then(function (r) { return r.json(); })
        .then(function (data) {
          if (data.ok) applyState(data.playing);
        })
        .catch(function (e) { setStatus('❌ ' + e.message); })
        .finally(function () { _toggling = false; });
    };

    var doNext = function () {
      fetch(BASE + 'next').then(function(r){ return r.json(); })
      .then(function() { setTimeout(pollStatus, 300); }); // 曲送り後に即座に情報を再取得
    };

    var doPrev = function () {
      fetch(BASE + 'prev').then(function(r){ return r.json(); })
      .then(function() { setTimeout(pollStatus, 300); }); // 曲戻し後に即座に情報を再取得
    };

    navigator.mediaSession.setActionHandler('play',          doToggle);
    navigator.mediaSession.setActionHandler('pause',         doToggle);
    navigator.mediaSession.setActionHandler('nexttrack',     doNext);
    navigator.mediaSession.setActionHandler('previoustrack', doPrev);

    toggleBtn.addEventListener('click', doToggle);
    nextBtn.addEventListener('click', doNext);
    prevBtn.addEventListener('click', doPrev);

    pollStatus();
  }

  activateBtn.addEventListener('click', activate, { once: true });
})();
</script>
</body>
</html>
"""

# ─── playerctl (MPRIS2 via DBus) ─────────────────────────────────────────────
def _get_dbus_addr():
    """DBus セッションソケットを /tmp/dbus-* から探す"""
    for s in glob.glob('/tmp/dbus-*'):
        try:
            if stat.S_ISSOCK(os.stat(s).st_mode):
                return f'unix:path={s}'
        except Exception:
            pass
    return None

def _playerctl(args):
    """playerctl コマンドを実行して (ok, stdout) を返す"""
    addr = _get_dbus_addr()
    if not addr:
        return False, ''
    env = {'DBUS_SESSION_BUS_ADDRESS': addr, 'PATH': '/usr/local/bin:/usr/bin:/bin'}
    r = subprocess.run(
        ['playerctl', '--player=firefox,%any'] + args,
        env=env, capture_output=True, timeout=3, cwd='/', text=True
    )
    return r.returncode == 0, r.stdout.strip()

def get_ytm_status():
    """playerctl (MPRIS2) で再生状態と曲名を 1 回のコマンドで取得"""
    ok, out = _playerctl(['metadata', '--format', '{{status}}|||{{title}}|||{{artist}}'])
    if not ok or not out:
        return None
    parts = out.split('|||', 2)
    status = parts[0]
    title  = parts[1] if len(parts) > 1 else ''
    artist = parts[2] if len(parts) > 2 else ''
    return {
        'playing': status == 'Playing',
        'title':   title  or None,
        'artist':  artist or None,
    }

# ─── 統合制御 ─────────────────────────────────────────────────────────────────
def toggle_ytm():
    ok, _ = _playerctl(['play-pause'])
    if ok:
        time.sleep(0.15)
        s = get_ytm_status()
        playing = s['playing'] if s else None
    else:
        playing = None
    return ok, playing

def next_track():
    ok, _ = _playerctl(['next'])
    return ok

def prev_track():
    ok, _ = _playerctl(['previous'])
    return ok

# ─── HTTP サーバー ────────────────────────────────────────────────────────────
class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, fmt, *args): pass # ログを減らす

    def _send_json(self, data):
        body = json.dumps(data).encode('utf-8')
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _serve(self):
        path = self.path.split('?')[0].rstrip('/')
        if path in ('', '/'):
            body = HTML_CONTENT.encode('utf-8')
            self.send_response(200)
            self.send_header('Content-Type', 'text/html; charset=utf-8')
            self.send_header('Content-Length', str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        elif path == '/status':
            s = get_ytm_status()
            playing = s['playing'] if s else None
            title   = s['title']  if s else None
            artist  = s['artist'] if s else None
            self._send_json({'playing': playing, 'title': title, 'artist': artist})
        elif path == '/toggle':
            ok, playing = toggle_ytm()
            self._send_json({'ok': ok, 'playing': playing})
        elif path == '/next':
            self._send_json({'ok': next_track()})
        elif path == '/prev':
            self._send_json({'ok': prev_track()})
        else:
            self.send_response(404)
            self.end_headers()

    do_GET = _serve

socketserver.TCPServer.allow_reuse_address = True
print('[media-server] :8080 で起動します', file=sys.stderr)
with socketserver.TCPServer(('0.0.0.0', 8080), Handler) as httpd:
    httpd.serve_forever()
PYEOF

chmod +x /usr/local/bin/media-server.py

# ─── Selkies VNC ページのタイトル・アイコンカスタマイズ ─────────────────────────
SELKIES_WEB="/usr/share/selkies/web"

# index.html に <title> を追加（もし未設定なら）
if [ -f "${SELKIES_WEB}/index.html" ] && ! grep -q "<title>" "${SELKIES_WEB}/index.html" 2>/dev/null; then
    sed -i 's|</head>|<title>Youtube Music VNC</title></head>|' "${SELKIES_WEB}/index.html"
fi

# manifest.json の名前とサイズを更新
if [ -f "${SELKIES_WEB}/manifest.json" ]; then
    sed -i 's|"name": "Firefox"|"name": "Youtube Music VNC"|' "${SELKIES_WEB}/manifest.json"
    sed -i 's|"short_name": "Firefox"|"short_name": "YTM"|' "${SELKIES_WEB}/manifest.json"
    sed -i 's|"sizes": "180x180"|"sizes": "192x192"|' "${SELKIES_WEB}/manifest.json"
fi

# YouTube Music アイコンを Selkies web ディレクトリにコピー
# (アイコンは Dockerfile で /usr/local/share/ytm-icon.png に保存済み)
if [ -f "/usr/local/share/ytm-icon.png" ]; then
    cp -f /usr/local/share/ytm-icon.png "${SELKIES_WEB}/icon.png"
fi

# ─── s6 サービス登録 ──────────────────────────────────────────────────────────
mkdir -p /etc/services.d/svc-media-server
cat << 'EOF' > /etc/services.d/svc-media-server/run
#!/usr/bin/execlineb -P
fdmove -c 2 1
s6-setuidgid abc
/lsiopy/bin/python3 /usr/local/bin/media-server.py
EOF
chmod +x /etc/services.d/svc-media-server/run

echo "=== メディア統合サーバー セットアップ完了 ==="
