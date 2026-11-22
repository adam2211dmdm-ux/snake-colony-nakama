# Snake Colony — Nakama server on Railway (free trial, no card)
# Single service: CockroachDB (low-memory single node) + Nakama 3.26.0
# in ONE container, so a phone-only demo needs just 1 service + 1 TCP proxy.
# Same versions + same matchmaker flags already verified locally 2026-11-22.
# Railway builds linux/amd64, so the native binaries are used (no Docker-in-Docker).
FROM debian:bookworm-slim

ENV NAKAMA_VERSION=v3.26.0
ENV COCKROACH_VERSION=v24.3.9
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update -y \
 && apt-get install -y --no-install-recommends curl ca-certificates tar procps \
 && rm -rf /var/lib/apt/lists/*

# CockroachDB (amd64) — the database Nakama stores accounts + matches in.
RUN curl -sSL -o /tmp/cockroach.tgz \
      "https://binaries.cockroachdb.com/cockroach-${COCKROACH_VERSION}.linux-amd64.tgz" \
 && tar xzf /tmp/cockroach.tgz -C /tmp \
 && cp "/tmp/cockroach-${COCKROACH_VERSION}.linux-amd64/cockroach" /usr/local/bin/cockroach \
 && rm -rf /tmp/cockroach.tgz "/tmp/cockroach-${COCKROACH_VERSION}.linux-amd64" \
 && cockroach --version | head -1

# Nakama server (amd64).
RUN curl -sSL -o /tmp/nakama.tar.gz \
      "https://github.com/heroiclabs/nakama/releases/download/${NAKAMA_VERSION}/nakama-${NAKAMA_VERSION#v}-linux-amd64.tar.gz" \
 && mkdir -p /opt/nakama \
 && tar xzf /tmp/nakama.tar.gz -C /opt/nakama \
 && chmod +x /opt/nakama/nakama \
 && rm /tmp/nakama.tar.gz \
 && /opt/nakama/nakama version || true

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Game API (the only port Railway needs to expose via TCP Proxy).
EXPOSE 7350

ENTRYPOINT ["/entrypoint.sh"]
