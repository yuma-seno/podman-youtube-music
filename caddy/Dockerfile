# DuckDNS DNS-01 チャレンジモジュール付き Caddy をビルド
FROM caddy:builder AS builder

RUN xcaddy build \
    --with github.com/caddy-dns/duckdns

# 最終イメージは caddy:latest ベース + カスタムバイナリのみ
FROM caddy:latest

COPY --from=builder /usr/bin/caddy /usr/bin/caddy
