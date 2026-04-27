# podman-youtube-music

在宅ワーク中に**自宅サーバーでYouTube Musicを流しながら、会社PC（Windows）から操作する**ためのシステムです。

- 自宅のサーバーで **Firefox** をコンテナとして動かし、YouTube Musicをキオスクモードで再生
- 会社PCのブラウザからHTTPSで接続して音楽を聴く
- `/media/` ページをバックグラウンドタブで開いておくと、**Windowsのメディアコントロール**（通知センター Win+A、メディアキーなど）から再生/停止/曲送りができる

> [!WARNING]
> **このシステムはプライベートLAN内（自宅ネットワーク）での利用を前提としています。**
>
> Selkies デスクトップ画面には認証なしでアクセスでき、YouTube MusicのログインセッションやGoogleアカウント情報が丸見えになります。
> インターネットに公開する場合は、Caddy の認証設定を必ず追加してください。
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
            │ コンテナ内部ネットワーク
    ┌───────┴──────────────────────────────┐
    │  Firefox (LinuxServer Selkies イメージ) │
    │  ┌──────────────────────┐            │
    │  │ Selkies (WebRTC) :3000│ ← デスクトップ画面 (メイン)
    │  ├──────────────────────┤            │
    │  │ 音楽リモコン :8080    │ ← 再生/停止/曲送りUI
    │  └──────────────────────┘            │
    │  YouTube Music (--kiosk モード)       │
    └──────────────────────────────────────┘
```

### アクセスURL

| パス | 内容 |
|---|---|
| `https://[DOMAIN]:8443/` | Selkies デスクトップ（YouTube Musicの設定・ログインに使用）タブ名: "Youtube Music VNC" |
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

### 2. イメージをビルドして起動

```bash
./scripts/start.sh
``` 証明書の取得が行われます（数分かかる場合があります）。

### 3. Selkies でYouTube Musicにログイン

```
https://[DOMAIN]:8443/
```

Selkies のデスクトップ画面が表示されたら、Firefox の YouTube Music にGoogleアカウントでログインします。

> **Firefoxのセッション持続について**
> FirefoxにはChrome 147+の DBSC（Device Bound Session Credentials）がないため、コンテナを再起動してもFirefoxプロファイル（`./config/.mozilla/firefox/`）が永続化されている限りログイン状態が維持されます。

### 4. systemd による自動起動・自動停止の設定

PC起動時に自動でコンテナを起動し、シャットダウン時に Firefox を正常終了させてからコンテナを停止します。

```bash
./scripts/install.sh
```

インストーラーが以下を自動で行います：
- systemd ユーザーサービスの生成・インストール
- PC起動時の自動スタートを有効化

> **ログアウト後もコンテナを動かし続けたい場合**（サーバー用途）は追加で実行：
> ```bash
> loginctl enable-linger
> ```

---

## 日常的な操作

| 操作 | コマンド |
|---|---|
| 再起動（更新時など） | `./scripts/start.sh` |
| **正常停止**（シャットダウン前） | `./scripts/stop.sh` または `systemctl --user stop podman-youtube-music` |
| 状態確認 | `systemctl --user status podman-youtube-music` |
| アンインストール | `./scripts/uninstall.sh` |

> [!IMPORTANT]
> PCをシャットダウンする場合は systemd が自動で `scripts/stop.sh` を実行します。
> ただし手動で停止するときは必ず `./scripts/stop.sh` を使ってください。
> `podman stop` や `podman-compose down` を直接実行すると Firefox が強制終了（SIGKILL）され、
> Firefoxプロファイルが正しく保存されない可能性があります。

---

## 起動スクリプト (`scripts/start.sh`) の動作

```
[0/4] 実行ユーザー確認       → UID/GID を取得してコンテナに渡す
[1/4] コンテナ停止・削除     → Firefox を SIGTERM で正常終了させてから停止
[2/4] ネットワーク削除       → aardvark-dns のリセット（名前解決の不整合を防ぐ）
[3/4] ロックファイル掃除      → Wayland/Selkies/Firefox の残留ゴミを削除
[4/4] コンテナ起動           → podman-compose up -d
```

---

## ディレクトリ構成

```
.
├── compose.yaml                        # コンテナ定義
├── scripts/
│   ├── start.sh                        # 起動スクリプト
│   ├── stop.sh                         # 正常停止スクリプト
│   ├── install.sh                      # systemd サービスのインストール
│   ├── uninstall.sh                    # systemd サービスのアンインストール
│   └── podman-youtube-music.service    # systemd ユーザーサービステンプレート
├── .env.example                        # 環境変数テンプレート
├── caddy/
│   ├── Dockerfile                      # DuckDNSモジュール付きCaddyビルド
│   └── Caddyfile                       # リバースプロキシ設定
├── firefox/
│   ├── Dockerfile                      # LinuxServer Firefox + playerctl
│   └── custom-cont-init.d/
│       └── 99-media-integration.sh     # 音楽リモコンサーバーのセットアップ
└── config/                             # Firefoxプロファイル（自動生成・永続化）
    └── .mozilla/firefox/               # ログイン情報・Cookie など
```

> **注**: `firefox/` ディレクトリ内のサービスはコンテナ定義上でも `firefox` という名前で管理されています。

---

## 技術的詳細

### Caddy コンテナ

**Dockerfile のビルドステップ：**
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

    handle_path /media* { reverse_proxy firefox:8080 }  # リモコンUI
    handle              { reverse_proxy firefox:3000 }  # Selkies
}
```

### Firefox コンテナ

[LinuxServer Firefox](https://docs.linuxserver.io/images/docker-firefox/) イメージをベースに、[Selkies](https://github.com/selkies-project/selkies) による WebRTC デスクトップストリーミングを提供します。Firefox は `labwc`（Waylandコンポジター）の `/defaults/autostart` から起動されます。

**Dockerfile の追加インストール：**
```dockerfile
FROM lscr.io/linuxserver/firefox:latest
RUN chmod o+x /usr/bin/lsiown
RUN apt-get update && apt-get install -y --no-install-recommends playerctl \
    && rm -rf /var/lib/apt/lists/*
```

**Firefox 起動フラグ（`compose.yaml` の `FIREFOX_CLI`）：**

| フラグ | 目的 |
|---|---|
| `--kiosk` | フルスクリーン・キオスクモード（アドレスバー非表示） |

> **`--remote-debugging-port` を使わない理由**
> Chromium DevTools Protocol (CDP) のリモートデバッグポートを有効にすると、Google がブラウザを「リモートコントロール下にある」と検出し、Googleアカウントへのログインをブロックします。そのため、このシステムでは CDP を一切使用しません。

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

**制御の仕組み（playerctl / MPRIS2）：**

Firefox が YouTube Music を再生すると、MPRIS2 プレーヤーとして DBus セッションに登録されます。音楽リモコンサーバーは `playerctl` 経由でこれを制御します。

```
playerctl (MPRIS2 via DBus)
  │  su abc -s /bin/sh -c "DBUS_SESSION_BUS_ADDRESS=unix:path=/tmp/dbus-XXX playerctl --player=firefox,%any ..."
  │  DBus セッションソケット: /tmp/dbus-* (uid=1000 のファイルを検索)
  └── playerctl [status|play-pause|next|previous|metadata title|metadata artist]
```

**Windowsメディアコントロール連携：**

`/media/` ページで「有効化する」を押すと：

1. **サイレント音声（無音WAV）を再生** — ブラウザがアクティブなメディアセッションを持っているとOSに認識させる
2. **[Media Session API](https://developer.mozilla.org/ja/docs/Web/API/Media_Session_API) に登録** — 再生/停止/曲送りのハンドラーを設定
3. **1秒ごとにサーバーをポーリング** — playerctl で取得した現在の曲名・アーティスト名・再生状態をOSに報告

これにより、会社PCで仕事をしながら **Win+A（通知センター）やメディアキー（キーボード）** で曲の操作が可能になります。

### データ永続化

```
./config/  →  コンテナ内 /config/
    └── .mozilla/firefox/
            └── [profile]/
                    ├── cookies.sqlite   ← ログインセッション
                    ├── places.sqlite    ← 閲覧履歴
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

### 再起動後にYouTube Musicへの再ログインが必要になる

`./config/.mozilla/` が正しくマウントされているか確認してください。FirefoxにはChromeのDBSC（Device Bound Session Credentials）がないため、プロファイルが永続化されていればコンテナ再起動後もログイン状態は維持されます。

```bash
ls ./config/.mozilla/firefox/
```

### Selkies 画面が表示されない

`scripts/start.sh` を再実行してください。ロックファイルが自動でクリーンアップされます。

```bash
./scripts/start.sh
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
  ./scripts/start.sh
