#!/usr/bin/env bash
set -euo pipefail

echo "=========================================="
echo "  Kali-OpenClaw — Starting up"
echo "=========================================="

# ---- 1. Install extra apt packages if requested ----
if [ -n "${OPENCLAW_DOCKER_APT_PACKAGES:-}" ]; then
    echo "[entrypoint] Installing extra packages: ${OPENCLAW_DOCKER_APT_PACKAGES}"
    apt-get update -qq
    # shellcheck disable=SC2086
    apt-get install -y --no-install-recommends ${OPENCLAW_DOCKER_APT_PACKAGES}
    rm -rf /var/lib/apt/lists/*
    echo "[entrypoint] Extra packages installed."
fi

# ---- 2. Generate OpenClaw config from env vars ----
echo "[entrypoint] Running configure.js..."
node /opt/kali-openclaw/configure.js

# ---- 3. Set up nginx basic auth ----
AUTH_USERNAME="${AUTH_USERNAME:-admin}"
AUTH_PASSWORD="${AUTH_PASSWORD:-}"

if [ -n "${AUTH_PASSWORD}" ]; then
    echo "[entrypoint] Setting up basic auth for user: ${AUTH_USERNAME}"
    htpasswd -cb /etc/nginx/.htpasswd "${AUTH_USERNAME}" "${AUTH_PASSWORD}"
else
    echo "[entrypoint] WARNING: No AUTH_PASSWORD set — web UI is unprotected!"
    rm -f /etc/nginx/.htpasswd
fi

# ---- 4. Ensure data directories exist ----
mkdir -p /data/.openclaw /data/workspace

# ---- 5. Start nginx ----
echo "[entrypoint] Starting nginx..."
nginx

# ---- 6. Start OpenClaw gateway (foreground) ----
echo "[entrypoint] Starting OpenClaw gateway on :18789..."
exec openclaw-gateway \
    --config /data/.openclaw/config.json \
    --host 0.0.0.0 \
    --port 18789
