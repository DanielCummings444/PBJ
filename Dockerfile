# ============================================================
# OpenClaw Quant + Hacker Toolkit — Zeabur Edition
# Multi-stage build: fetch OpenClaw binary, then install
# all 232+ tools onto Kali Linux at build time.
#
# Deploy to Zeabur → enter API keys → ready to go.
# ============================================================

# ── Stage 1: Download OpenClaw release ──────────────────────
FROM debian:bookworm-slim AS fetcher

RUN apt-get update && apt-get install -y --no-install-recommends \
        curl ca-certificates jq \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build

RUN LATEST=$(curl -fsSL https://api.github.com/repos/nicepkg/openclaw/releases/latest \
        | jq -r '.tag_name') && \
    echo "Fetching OpenClaw ${LATEST}" && \
    curl -fsSL -o openclaw-gateway \
        "https://github.com/nicepkg/openclaw/releases/download/${LATEST}/openclaw-gateway-linux-amd64" && \
    chmod +x openclaw-gateway

# ── Stage 2: Full toolkit on Kali Linux ─────────────────────
FROM kalilinux/kali-rolling

LABEL maintainer="openclaw-toolkit"
LABEL description="OpenClaw AI assistant on Kali Linux with 232+ quant, hacker, and OSINT tools pre-installed"

ENV DEBIAN_FRONTEND=noninteractive
ENV NEEDRESTART_MODE=a

# Base packages needed before the big installer runs
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
        lsb-release \
        gnupg \
        software-properties-common \
    && rm -rf /var/lib/apt/lists/*

# Copy OpenClaw binary from fetcher stage
COPY --from=fetcher /build/openclaw-gateway /usr/local/bin/openclaw-gateway

# Create directories
RUN mkdir -p /data/.openclaw /data/workspace /opt/toolkit

# Copy the full installer script
COPY scripts/openclaw_zeabur_installer.sh /opt/openclaw-installer.sh
RUN chmod +x /opt/openclaw-installer.sh

# ── Run the full toolkit installer at build time ─────────────
# This bakes all 232+ tools directly into the Docker image.
# DOCKER_BUILD=yes tells the installer to skip service starts
# and Docker-in-Docker operations.
# SKIP_DOCKER=yes because we can't run Docker inside a build.
# TOOLKIT_DIR=/opt/toolkit puts everything in the image layer.
RUN DOCKER_BUILD=yes \
    SKIP_DOCKER=yes \
    TOOLKIT_DIR=/opt/toolkit \
    ZEABUR_DATA_DIR=/data \
    /opt/openclaw-installer.sh \
    || echo "Installer completed with some failures (non-fatal)"

# ── Copy runtime scripts and configs ────────────────────────
COPY scripts/configure.js /opt/kali-openclaw/configure.js
COPY scripts/entrypoint.sh /opt/kali-openclaw/entrypoint.sh
RUN chmod +x /opt/kali-openclaw/entrypoint.sh

COPY nginx/default.conf /etc/nginx/sites-available/default

# ── Ensure environment is baked into the image ───────────────
ENV PATH="/usr/local/go/bin:/opt/toolkit/go/bin:/opt/toolkit/cargo/bin:/opt/toolkit/foundry/bin:/opt/toolkit/npm-global/bin:${PATH}"
ENV GOPATH="/opt/toolkit/go"
ENV CARGO_HOME="/opt/toolkit/cargo"
ENV TOOLS_DIR="/opt/toolkit/tools"
ENV TOOLKIT_DIR="/opt/toolkit"

WORKDIR /data/workspace

EXPOSE 8080

VOLUME ["/data"]

ENTRYPOINT ["/opt/kali-openclaw/entrypoint.sh"]
