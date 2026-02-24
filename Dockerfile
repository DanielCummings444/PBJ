# ============================================================
# Kali-OpenClaw — OpenClaw AI assistant on Kali Linux
# Multi-stage build: fetch OpenClaw, then run on Kali Rolling
# ============================================================

# Stage 1: Download OpenClaw release
FROM debian:bookworm-slim AS fetcher

RUN apt-get update && apt-get install -y --no-install-recommends \
        curl ca-certificates jq \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build

# Fetch the latest OpenClaw gateway release (Linux amd64)
RUN LATEST=$(curl -fsSL https://api.github.com/repos/nicepkg/openclaw/releases/latest \
        | jq -r '.tag_name') && \
    echo "Fetching OpenClaw ${LATEST}" && \
    curl -fsSL -o openclaw-gateway \
        "https://github.com/nicepkg/openclaw/releases/download/${LATEST}/openclaw-gateway-linux-amd64" && \
    chmod +x openclaw-gateway

# Stage 2: Runtime on Kali Linux Rolling
FROM kalilinux/kali-rolling

LABEL maintainer="kali-openclaw"
LABEL description="OpenClaw AI assistant on Kali Linux"

ENV DEBIAN_FRONTEND=noninteractive

# Install base packages: nginx, Node.js (for configure.js), common tools
RUN apt-get update && apt-get install -y --no-install-recommends \
        nginx \
        apache2-utils \
        nodejs \
        npm \
        curl \
        ca-certificates \
        jq \
        procps \
        sudo \
        git \
        wget \
    && rm -rf /var/lib/apt/lists/*

# Uncomment below to bake Kali tools into the image:
# RUN apt-get update && apt-get install -y \
#     nmap sqlmap nikto metasploit-framework \
#     && rm -rf /var/lib/apt/lists/*

# Copy OpenClaw binary from fetcher stage
COPY --from=fetcher /build/openclaw-gateway /usr/local/bin/openclaw-gateway

# Create data directories
RUN mkdir -p /data/.openclaw /data/workspace

# Copy nginx config
COPY nginx/default.conf /etc/nginx/sites-available/default

# Copy scripts
COPY scripts/configure.js /opt/kali-openclaw/configure.js
COPY scripts/entrypoint.sh /opt/kali-openclaw/entrypoint.sh
RUN chmod +x /opt/kali-openclaw/entrypoint.sh

WORKDIR /data/workspace

EXPOSE 8080

VOLUME ["/data"]

ENTRYPOINT ["/opt/kali-openclaw/entrypoint.sh"]
