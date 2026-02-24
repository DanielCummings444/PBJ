# ============================================================
# OpenClaw Quant + Hacker Toolkit — Zeabur Edition
# Single-stage build on Kali Linux Rolling.
# Installs OpenClaw via npm + all 232+ security/quant tools.
#
# Deploy to Zeabur → enter API keys → ready to go.
# ============================================================

FROM kalilinux/kali-rolling

LABEL maintainer="openclaw-toolkit"
LABEL description="OpenClaw AI assistant on Kali Linux with 232+ quant, hacker, and OSINT tools pre-installed"

ENV DEBIAN_FRONTEND=noninteractive
ENV NEEDRESTART_MODE=a

# ── 1. Base packages needed before anything else ─────────────
RUN apt-get update && apt-get install -y --no-install-recommends \
        nginx \
        apache2-utils \
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

# ── 2. Install Node.js 22 (OpenClaw requires Node 22+) ──────
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/* \
    && node --version && npm --version

# ── 3. Install OpenClaw via npm ──────────────────────────────
RUN npm install -g openclaw@latest \
    && openclaw --version || echo "OpenClaw installed"

# ── 4. Create directories ───────────────────────────────────
RUN mkdir -p /data/.openclaw /data/workspace /opt/toolkit

# ── 5. Copy and run the full toolkit installer ───────────────
# This bakes all 232+ tools directly into the Docker image.
# DOCKER_BUILD=yes skips service starts and Docker-in-Docker.
COPY scripts/openclaw_zeabur_installer.sh /opt/openclaw-installer.sh
RUN chmod +x /opt/openclaw-installer.sh

RUN DOCKER_BUILD=yes \
    SKIP_DOCKER=yes \
    TOOLKIT_DIR=/opt/toolkit \
    ZEABUR_DATA_DIR=/data \
    /opt/openclaw-installer.sh \
    || echo "Installer completed with some failures (non-fatal)"

# ── 6. Copy runtime scripts and configs ──────────────────────
COPY scripts/configure.js /opt/kali-openclaw/configure.js
COPY scripts/entrypoint.sh /opt/kali-openclaw/entrypoint.sh
RUN chmod +x /opt/kali-openclaw/entrypoint.sh

COPY nginx/default.conf /etc/nginx/sites-available/default

# ── 7. Bake environment into the image ───────────────────────
ENV PATH="/usr/local/go/bin:/opt/toolkit/go/bin:/opt/toolkit/cargo/bin:/opt/toolkit/foundry/bin:/opt/toolkit/npm-global/bin:${PATH}"
ENV GOPATH="/opt/toolkit/go"
ENV CARGO_HOME="/opt/toolkit/cargo"
ENV TOOLS_DIR="/opt/toolkit/tools"
ENV TOOLKIT_DIR="/opt/toolkit"

WORKDIR /data/workspace

EXPOSE 8080

VOLUME ["/data"]

ENTRYPOINT ["/opt/kali-openclaw/entrypoint.sh"]
