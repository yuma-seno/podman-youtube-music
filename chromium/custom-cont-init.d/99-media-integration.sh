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
import re
import socketserver
import subprocess
import sys
import time
import urllib.request

# ─── HTML ────────────────────────────────────────────────────────────────────
HTML_CONTENT = """\
<!DOCTYPE html>
<html lang="ja">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>YouTube Music リモコン</title>
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

    // 3秒ごとの定期ポーリング
    setInterval(pollStatus, 3000);

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
      .then(function() { setTimeout(pollStatus, 500); }); // 曲送り後に即座に情報を再取得
    };

    var doPrev = function () {
      fetch(BASE + 'prev').then(function(r){ return r.json(); })
      .then(function() { setTimeout(pollStatus, 500); }); // 曲戻し後に即座に情報を再取得
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

# ─── CDP 共通ヘルパー ─────────────────────────────────────────────────────────
def _cdp_ws():
    """YTM タブの WebSocket 接続を返す。見つからなければ None"""
    try:
        import websocket as _ws_mod
    except ImportError:
        return None
    try:
        with urllib.request.urlopen('http://127.0.0.1:9222/json', timeout=2) as resp:
            tabs = json.loads(resp.read().decode())
        yt = next(
            (t for t in tabs
             if 'music.youtube.com' in t.get('url', '')
             and t.get('type') == 'page'),
            None,
        )
        if not yt:
            return None
        ws_url = yt['webSocketDebuggerUrl'].replace('localhost', '127.0.0.1')
        return _ws_mod.create_connection(ws_url, timeout=3)
    except Exception as e:
        print(f'[cdp] 接続エラー: {e}', file=sys.stderr)
        return None

def _cdp_eval(ws, expr, seq_id=1):
    """Runtime.evaluate を実行して value を返す"""
    ws.send(json.dumps({
        'id': seq_id,
        'method': 'Runtime.evaluate',
        'params': {'expression': expr, 'returnByValue': True},
    }))
    res = json.loads(ws.recv())
    return res.get('result', {}).get('result', {}).get('value')

# ─── YouTube Music DOM制御 (直接要素を指定してクリック) ──────────────────────
def click_ytm_element(selector):
    """CSSセレクタで指定した要素をクリックする"""
    ws = _cdp_ws()
    if not ws:
        return False
    try:
        expr = f'(()=>{{var e=document.querySelector("{selector}");if(e){{e.click();return true;}}return false;}})()'
        result = _cdp_eval(ws, expr)
        print(f'[cdp] click "{selector}" → {result}', file=sys.stderr)
        return bool(result)
    except Exception as e:
        print(f'[cdp] click エラー: {e}', file=sys.stderr)
        return False
    finally:
        try:
            ws.close()
        except Exception:
            pass

def toggle_via_cdp():
    """YTMの再生/一時停止ボタンを直接クリックする"""
    return click_ytm_element('ytmusic-player-bar #play-pause-button')

def get_ytm_status():
    """CDPで再生状態と曲名を取得して dict で返す (DOMから直接抽出)"""
    ws = _cdp_ws()
    if not ws:
        return None
    try:
        expr = '''(() => {
            var v = document.querySelector("video");
            var t = document.querySelector("ytmusic-player-bar .title");
            var a = document.querySelector("ytmusic-player-bar .subtitle");
            return JSON.stringify({
                playing: v ? !v.paused : null,
                title: t ? t.textContent.trim() : null,
                artist: a ? a.textContent.trim() : null
            });
        })()'''
        raw_json = _cdp_eval(ws, expr)
        if raw_json:
            return json.loads(raw_json)
        return None
    except Exception as e:
        print(f'[cdp] status エラー: {e}', file=sys.stderr)
        return None
    finally:
        try:
            ws.close()
        except Exception:
            pass

# ─── Toggle: playerctl (MPRIS フォールバック) ─────────────────────────────────
def _get_dbus_addr():
    for env_path in glob.glob('/proc/*/environ'):
        try:
            data = open(env_path, 'rb').read()
            env = {}
            for seg in data.split(b'\x00'):
                if b'=' in seg:
                    k, v = seg.split(b'=', 1)
                    env[k.decode(errors='ignore')] = v.decode(errors='ignore')
            status_path = env_path.replace('environ', 'status')
            uid_m = re.search(r'Uid:\s+(\d+)', open(status_path).read())
            if uid_m and int(uid_m.group(1)) == 999 and 'DBUS_SESSION_BUS_ADDRESS' in env:
                return env['DBUS_SESSION_BUS_ADDRESS']
        except Exception:
            continue
    return None

def toggle_via_playerctl():
    addr = _get_dbus_addr()
    if not addr: return False
    env = {'DBUS_SESSION_BUS_ADDRESS': addr, 'PATH': '/usr/local/bin:/usr/bin:/bin'}
    r = subprocess.run(
        ['playerctl', '--player=chromium,Chromium,%any', 'play-pause'],
        env=env, capture_output=True, timeout=3, cwd='/'
    )
    return r.returncode == 0

# ─── 統合制御 ─────────────────────────────────────────────────────────────────
_is_playing = False

def toggle_ytm():
    global _is_playing
    ok = toggle_via_cdp() or toggle_via_playerctl()
    if ok:
        time.sleep(0.15)
        s = get_ytm_status()
        _is_playing = s['playing'] if s and s['playing'] is not None else (not _is_playing)
    return ok, _is_playing

# ─── HTTP サーバー ────────────────────────────────────────────────────────────
class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, fmt, *args): pass # ログを減らす

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
            if s and s['playing'] is not None:
                playing = s['playing']
                title   = s.get('title')
                artist  = s.get('artist')
            else:
                playing = _is_playing
                title, artist = None, None
            body = json.dumps({'playing': playing, 'title': title, 'artist': artist}).encode('utf-8')
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Content-Length', str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        elif path == '/toggle':
            ok, playing = toggle_ytm()
            body = json.dumps({'ok': ok, 'playing': playing}).encode('utf-8')
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Content-Length', str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        elif path == '/next':
            ok = click_ytm_element('ytmusic-player-bar .next-button')
            body = json.dumps({'ok': ok}).encode('utf-8')
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Content-Length', str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        elif path == '/prev':
            ok = click_ytm_element('ytmusic-player-bar .previous-button')
            body = json.dumps({'ok': ok}).encode('utf-8')
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Content-Length', str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        else:
            self.send_response(404)
            self.end_headers()

    do_GET  = _serve
    do_POST = _serve

socketserver.TCPServer.allow_reuse_address = True
print('[media-server] :8080 で起動します', file=sys.stderr)
with socketserver.TCPServer(('0.0.0.0', 8080), Handler) as httpd:
    httpd.serve_forever()
PYEOF

chmod +x /usr/local/bin/media-server.py

# ─── s6 サービス登録 ──────────────────────────────────────────────────────────
mkdir -p /etc/services.d/svc-media-server
cat << 'EOF' > /etc/services.d/svc-media-server/run
#!/usr/bin/execlineb -P
fdmove -c 2 1
/lsiopy/bin/python3 /usr/local/bin/media-server.py
EOF
chmod +x /etc/services.d/svc-media-server/run

echo "=== メディア統合サーバー セットアップ完了 ==="