# podman-youtube-music

在宅ワーク中に**自宅サーバーでYouTube Musicを流しながら、会社PC（Windows）から操作する**ためのシステムです。

- 自宅のサーバーでChromiumをコンテナとして動かし、YouTube Musicをキオスクモードで再生
- 会社PCのブラウザからHTTPSで接続して音楽を聴く
- `/media/` ページをバックグラウンドタブで開いておくと、**Windowsのメディアコントロール**（通知センター Win+A、メディアキーなど）から再生/停止/曲送りができる

> [!WARNING]
> **このシステムはプライベートLAN内（自宅ネットワーク）での利用を前提としています。**
>
> KasmVNC画面には認証なしでアクセスでき、YouTube MusicのログインセッションやGoogleアカウント情報が丸見えになります。
> インターネットに公開する場合は、KasmVNC / Caddy の認証設定を必ず追加してください。
> **ポートフォワードの宛先を自宅内の信頼できる端末のみに限定することを強く推奨します。**

## 概要

```
外部ブラウザ / スマートフォン
        │  HTTPS :8443
        ▼
┌───────────────────────────┐
│  Caddy (リバースプロキシ)  │  ← Let's Encrypt 証明書を自動取得
│  DuckDNS DNS-01 チャレンジ │
└───────────┬───────────────┘
            │ Pod 内部ネットワーク
    ┌───────┴──────────────────────────┐
    │  Chromium (LinuxServer イメージ)   │
    │  ┌─────────────────┐             │
    │  │ KasmVNC :3000   │ ← VNCリモートデスクトップ画面 (メイン)
    │  ├─────────────────┤             │
    │  │ 音楽リモコン :8080│ ← 再生/停止/曲送りUI
    │  └─────────────────┘             │
    │  YouTube Music (キオスクモード)    │
    └──────────────────────────────────┘
```

### アクセスURL

| パス | 内容 |
|---|---|
| `https://[DOMAIN]:8443/` | KasmVNC リモートデスクトップ（YouTube Musicの設定・ログインなどに使用） |
| `https://[DOMAIN]:8443/media/` | Windowsメディアコントロール連携ページ（バックグラウンドで開いておく） |

---

## 必要なもの

- Podman + podman-compose がインストール済みのLinuxホスト
- [DuckDNS](https://www.duckdns.org/) アカウントとサブドメイン
- ルーターで **8443 ポート** をホストへポートフォワード設定済み

---

## セットアップ

### 1. `.env` ファイルを作成

```bash
cp .env.example .env
```

`.env` を編集して3つの値を設定します：

```ini
# DuckDNSのサブドメイン (例: my-music.duckdns.org)
DOMAIN=your-subdomain.duckdns.org

# DuckDNS APIトークン (duckdns.org ログイン後に右上に表示)
DUCKDNS_TOKEN=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx

# Let's Encrypt 通知用メールアドレス
ACME_EMAIL=your@email.com
```

### 2. 初回起動

```bash
./start.sh
```

初回はDockerイメージのビルドと Let's Encrypt 証明書の取得が行われます（数分かかる場合があります）。

### 3. アクセス

```
https://[DOMAIN]:8443/
```

KasmVNCの画面が表示されたら、YouTube Musicにログインします。

### 4. systemd による自動起動・自動停止の設定

PC起動時に自動でコンテナを起動し、シャットダウン時に Chrome を正常終了させてからコンテナを停止します。
**Cookie の永続化（ログイン維持）に必須の設定です。**

```bash
./install.sh
```

インストーラーが以下を自動で行います：
- systemd ユーザーサービスの生成・インストール
- PC起動時の自動スタートを有効化
- 既存の自動起動設定（`~/.profile` 等）との重複チェック

> **ログアウト後もコンテナを動かし続けたい場合**（サーバー用途）は追加で実行：
> ```bash
> loginctl enable-linger
> ```

---

## 日常的な操作

| 操作 | コマンド |
|---|---|
| 再起動（更新時など） | `./start.sh` |
| **正常停止**（シャットダウン前） | `./stop.sh` または `systemctl --user stop podman-youtube-music` |
| 状態確認 | `systemctl --user status podman-youtube-music` |
| アンインストール | `./uninstall.sh` |

> [!IMPORTANT]
> PC をシャットダウンする場合は systemd が自動で `stop.sh` を実行します。
> ただし手動で停止するときは必ず `./stop.sh` を使ってください。
> `podman stop` や `podman-compose down` を直接実行すると Chrome が強制終了（SIGKILL）され、
> Cookie がディスクに書き込まれずにログアウト状態になります。

---

## 起動スクリプト (`start.sh`) の動作

```
[0/4] 実行ユーザー確認       → UID/GID を取得してコンテナに渡す
[1/4] コンテナ停止・削除     → Chrome を SIGTERM で正常終了させてから停止
[2/4] ネットワーク削除       → aardvark-dns のリセット（名前解決の不整合を防ぐ）
[3/4] ロックファイル掃除      → X11/VNC/Chrome の残留ゴミを削除
[4/4] コンテナ起動           → podman-compose up -d
```

---

## ディレクトリ構成

```
.
├── compose.yaml                        # コンテナ定義
├── start.sh                            # 起動スクリプト
├── stop.sh                             # 正常停止スクリプト（Cookie 保存のため必須）
├── install.sh                          # systemd サービスのインストール
├── uninstall.sh                        # systemd サービスのアンインストール
├── podman-youtube-music.service        # systemd ユーザーサービステンプレート
├── .env.example                        # 環境変数テンプレート
├── caddy/
│   ├── Dockerfile                      # DuckDNSモジュール付きCaddyビルド
│   └── Caddyfile                       # リバースプロキシ設定
├── chromium/
│   ├── Dockerfile                      # LinuxServer Chromium + playerctl
│   └── custom-cont-init.d/
│       └── 99-media-integration.sh     # 音楽リモコンサーバーのセットアップ
└── config/                             # Chromiumプロファイル（自動生成・永続化）
    └── .config/chromium/Default/       # ログイン情報・Cookie・履歴など
```

---

## 技術的詳細

### Caddy コンテナ

[LinuxServer Chromium](https://docs.linuxserver.io/images/docker-chromium/) のベースイメージである [KasmVNC](https://github.com/kasmtech/KasmVNC) / Selkies の上に動作します。

**Caddy Dockerfile のビルドステップ：**
```dockerfile
FROM caddy:builder AS builder
RUN xcaddy build --with github.com/caddy-dns/duckdns
FROM caddy:latest
COPY --from=builder /usr/bin/caddy /usr/bin/caddy
```

[xcaddy](https://github.com/caddyserver/xcaddy) で DuckDNS DNS-01 チャレンジモジュールを組み込みます。通常のHTTP-01チャレンジはポート80が必要ですが、**DNS-01はポート80不要**でドメイン所有を証明できるため、家庭用ルーター環境に適しています。

**Caddyfile の構成：**
```
{env.DOMAIN}:8443 {
    tls { dns duckdns {env.DUCKDNS_TOKEN} }

    handle_path /media* { reverse_proxy chromium:8080 }  # リモコンUI
    handle              { reverse_proxy chromium:3000 }  # KasmVNC
}
```

### Chromium コンテナ

**Dockerfile の追加インストール：**
- `playerctl` — MPRIS (Media Player Remote Interfacing Specification) 対応の CLIツール。CDP 接続が失敗した場合のフォールバックとして使用。
- `websocket-client` (Python) — CDP の WebSocket 通信に使用。

**Chrome 起動フラグ：**

| フラグ | 目的 |
|---|---|
| `--kiosk` | フルスクリーン・キオスクモード（アドレスバー非表示） |
| `--no-first-run` | 初回起動ウィザードをスキップ |
| `--remote-debugging-port=9222` | CDP (Chrome DevTools Protocol) を有効化 |
| `--remote-debugging-address=127.0.0.1` | CDPはコンテナ内部からのみアクセス可能 |
| `--remote-allow-origins=*` | CDPへのオリジン制限を緩和 |
| `--no-sandbox` | rootless Podman環境での実行に必要 |
| `--password-store=basic` | キーリング非依存のCookie暗号化（再起動後もログイン維持） |

### 音楽リモコンサーバー (`99-media-integration.sh`)

コンテナ起動時に s6-overlay のサービスとして `/usr/local/bin/media-server.py` が自動起動し、ポート8080でHTTPサーバーとして待機します。

**エンドポイント：**

| エンドポイント | メソッド | 処理 |
|---|---|---|
| `/` | GET | リモコンUIのHTML |
| `/status` | GET | 再生状態・曲名・アーティスト名をJSON返却 |
| `/toggle` | GET | 再生/一時停止の切り替え |
| `/next` | GET | 次の曲へ |
| `/prev` | GET | 前の曲へ |

**制御の仕組み（二段階フォールバック）：**

```
CDP (Chrome DevTools Protocol)  ←── 優先
  │ DOM を直接操作
  │ document.querySelector("ytmusic-player-bar #play-pause-button").click()
  │
  └─ 失敗した場合
        ↓
     playerctl (MPRIS経由)
       │ DBUSアドレスをプロセス環境変数から動的に取得
       └── playerctl --player=chromium play-pause
```

**CDP による状態取得：**
```javascript
var v = document.querySelector("video");
var t = document.querySelector("ytmusic-player-bar .title");
var a = document.querySelector("ytmusic-player-bar .subtitle");
return JSON.stringify({
    playing: v ? !v.paused : null,
    title:   t ? t.textContent.trim() : null,
    artist:  a ? a.textContent.trim() : null
});
```

**Windows メディアコントロール連携：**

`/media/` ページで「有効化する」を押すと：

1. **サイレント音声（無音WAV）を再生** — これによりブラウザがアクティブなメディアセッションを持っているとOSに認識させる
2. **[Media Session API](https://developer.mozilla.org/ja/docs/Web/API/Media_Session_API) に登録** — 再生/停止/曲送りのハンドラーを設定
3. **3秒ごとにサーバーをポーリング** — CDPで取得した現在の曲名・アーティスト名・再生状態をOSに報告

これにより、会社PCで仕事をしながら **Win+A（通知センター）やメディアキー（キーボード）** で曲の操作が可能になります。タブを開いたままにしておくだけでよく、YouTube Musicの画面を前面に出す必要はありません。

### データ永続化

```
./config/  →  コンテナ内 /config/
    └── .config/chromium/Default/
            ├── Cookies        ← ログインセッション
            ├── History        ← 閲覧履歴
            ├── Preferences    ← Chrome設定
            └── ...
```

`caddy_data` / `caddy_config` はPodmanの名前付きボリュームとして永続化され、TLS証明書が再起動後も保持されます。

### rootless Podman 対応

```yaml
userns_mode: keep-id   # ホストのUID/GIDをコンテナ内にマッピング
user: "0:0"            # コンテナ内PID 1をrootとして起動
                       # → LinuxServer init が PUID/PGID で再マッピング
```

`lsiown` の実行権限を `o+x` にするのは、rootless環境でUID 1000として動作するPID 1がsetuidバイナリを実行できるようにするための対応です。

---

## トラブルシューティング

### 再起動後にYTMへの再ログインが必要になる

`--password-store=basic` フラグが有効になっているか確認してください（`compose.yaml` の `CHROME_CLI` に含まれているはずです）。

初めて `--password-store=basic` を有効にする場合は、古い暗号化Cookieとの競合を避けるため一度Cookieを削除してからログインし直してください：

```bash
rm ./config/.config/chromium/Default/Cookies
./start.sh
```

### コンテナが起動しない

```bash
podman logs yt_music_kiosk
podman logs yt_caddy
```

### 証明書が取得できない

- DuckDNS トークンが正しいか確認
- `DOMAIN` がDuckDNSで登録済みのサブドメインか確認
- `caddy_data` ボリュームを削除して再試行：
  ```bash
  podman volume rm podman-youtube-music_caddy_data
  ./start.sh
  ```

### VNC画面が表示されない

`./config` 内の残留ロックファイルが原因の場合があります。`start.sh` を再実行してください（自動でクリーンアップされます）。
