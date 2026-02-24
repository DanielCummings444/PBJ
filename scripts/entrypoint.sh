#!/usr/bin/env bash
set -euo pipefail

echo "=========================================="
echo "  OpenClaw Quant + Hacker Toolkit"
echo "  Starting up..."
echo "=========================================="

# ── 1. Source toolkit environment ────────────────────────────
if [[ -f /etc/profile.d/agent-toolkit.sh ]]; then
    source /etc/profile.d/agent-toolkit.sh
    echo "[entrypoint] Toolkit environment loaded"
fi

export PATH="/usr/local/go/bin:/opt/toolkit/go/bin:/opt/toolkit/cargo/bin:/opt/toolkit/foundry/bin:/opt/toolkit/npm-global/bin:$HOME/.cargo/bin:$HOME/.local/bin:$PATH"
export GOPATH="/opt/toolkit/go"
export CARGO_HOME="/opt/toolkit/cargo"
export TOOLS_DIR="/opt/toolkit/tools"

# ── 2. Ensure persistent data directories exist ─────────────
mkdir -p /data/.openclaw /data/workspace /data/logs

# ── 3. Write runtime API keys to config (from Zeabur env vars) ──
# These are set in the Zeabur dashboard and passed as env vars.
# Write them to a file so tools can source them.
ENV_FILE="/data/.openclaw/.env"
echo "# Auto-generated from Zeabur environment variables" > "$ENV_FILE"
echo "# $(date)" >> "$ENV_FILE"

# Trading & Market Data
[ -n "${ALPACA_API_KEY:-}" ]        && echo "export ALPACA_API_KEY=\"${ALPACA_API_KEY}\"" >> "$ENV_FILE"
[ -n "${ALPACA_SECRET_KEY:-}" ]     && echo "export ALPACA_SECRET_KEY=\"${ALPACA_SECRET_KEY}\"" >> "$ENV_FILE"
[ -n "${ALPACA_BASE_URL:-}" ]       && echo "export ALPACA_BASE_URL=\"${ALPACA_BASE_URL}\"" >> "$ENV_FILE"
[ -n "${BINANCE_API_KEY:-}" ]       && echo "export BINANCE_API_KEY=\"${BINANCE_API_KEY}\"" >> "$ENV_FILE"
[ -n "${BINANCE_SECRET_KEY:-}" ]    && echo "export BINANCE_SECRET_KEY=\"${BINANCE_SECRET_KEY}\"" >> "$ENV_FILE"
[ -n "${OKX_API_KEY:-}" ]          && echo "export OKX_API_KEY=\"${OKX_API_KEY}\"" >> "$ENV_FILE"
[ -n "${OKX_SECRET_KEY:-}" ]       && echo "export OKX_SECRET_KEY=\"${OKX_SECRET_KEY}\"" >> "$ENV_FILE"
[ -n "${OKX_PASSPHRASE:-}" ]       && echo "export OKX_PASSPHRASE=\"${OKX_PASSPHRASE}\"" >> "$ENV_FILE"
[ -n "${POLYGON_API_KEY:-}" ]      && echo "export POLYGON_API_KEY=\"${POLYGON_API_KEY}\"" >> "$ENV_FILE"

# OSINT & Recon
[ -n "${SHODAN_API_KEY:-}" ]       && echo "export SHODAN_API_KEY=\"${SHODAN_API_KEY}\"" >> "$ENV_FILE"
[ -n "${CENSYS_API_ID:-}" ]        && echo "export CENSYS_API_ID=\"${CENSYS_API_ID}\"" >> "$ENV_FILE"
[ -n "${CENSYS_API_SECRET:-}" ]    && echo "export CENSYS_API_SECRET=\"${CENSYS_API_SECRET}\"" >> "$ENV_FILE"
[ -n "${VT_API_KEY:-}" ]           && echo "export VT_API_KEY=\"${VT_API_KEY}\"" >> "$ENV_FILE"

# Social Media
[ -n "${REDDIT_CLIENT_ID:-}" ]     && echo "export REDDIT_CLIENT_ID=\"${REDDIT_CLIENT_ID}\"" >> "$ENV_FILE"
[ -n "${REDDIT_CLIENT_SECRET:-}" ] && echo "export REDDIT_CLIENT_SECRET=\"${REDDIT_CLIENT_SECRET}\"" >> "$ENV_FILE"
[ -n "${TWITTER_BEARER_TOKEN:-}" ] && echo "export TWITTER_BEARER_TOKEN=\"${TWITTER_BEARER_TOKEN}\"" >> "$ENV_FILE"

# AI / LLM
[ -n "${OPENAI_API_KEY:-}" ]       && echo "export OPENAI_API_KEY=\"${OPENAI_API_KEY}\"" >> "$ENV_FILE"
[ -n "${ANTHROPIC_API_KEY:-}" ]    && echo "export ANTHROPIC_API_KEY=\"${ANTHROPIC_API_KEY}\"" >> "$ENV_FILE"

# Blockchain
[ -n "${INFURA_PROJECT_ID:-}" ]    && echo "export INFURA_PROJECT_ID=\"${INFURA_PROJECT_ID}\"" >> "$ENV_FILE"
[ -n "${ALCHEMY_API_KEY:-}" ]      && echo "export ALCHEMY_API_KEY=\"${ALCHEMY_API_KEY}\"" >> "$ENV_FILE"
[ -n "${ETHERSCAN_API_KEY:-}" ]    && echo "export ETHERSCAN_API_KEY=\"${ETHERSCAN_API_KEY}\"" >> "$ENV_FILE"
[ -n "${DUNE_API_KEY:-}" ]         && echo "export DUNE_API_KEY=\"${DUNE_API_KEY}\"" >> "$ENV_FILE"

# Cloud
[ -n "${AWS_ACCESS_KEY_ID:-}" ]     && echo "export AWS_ACCESS_KEY_ID=\"${AWS_ACCESS_KEY_ID}\"" >> "$ENV_FILE"
[ -n "${AWS_SECRET_ACCESS_KEY:-}" ] && echo "export AWS_SECRET_ACCESS_KEY=\"${AWS_SECRET_ACCESS_KEY}\"" >> "$ENV_FILE"
[ -n "${AWS_DEFAULT_REGION:-}" ]    && echo "export AWS_DEFAULT_REGION=\"${AWS_DEFAULT_REGION}\"" >> "$ENV_FILE"

# Notifications
[ -n "${TELEGRAM_BOT_TOKEN:-}" ]   && echo "export TELEGRAM_BOT_TOKEN=\"${TELEGRAM_BOT_TOKEN}\"" >> "$ENV_FILE"
[ -n "${TELEGRAM_CHAT_ID:-}" ]     && echo "export TELEGRAM_CHAT_ID=\"${TELEGRAM_CHAT_ID}\"" >> "$ENV_FILE"
[ -n "${DISCORD_WEBHOOK_URL:-}" ]  && echo "export DISCORD_WEBHOOK_URL=\"${DISCORD_WEBHOOK_URL}\"" >> "$ENV_FILE"
[ -n "${SLACK_WEBHOOK_URL:-}" ]    && echo "export SLACK_WEBHOOK_URL=\"${SLACK_WEBHOOK_URL}\"" >> "$ENV_FILE"

chmod 600 "$ENV_FILE"
source "$ENV_FILE"
echo "[entrypoint] API keys configured"

# ── 4. Install extra apt packages if requested ──────────────
if [ -n "${OPENCLAW_DOCKER_APT_PACKAGES:-}" ]; then
    echo "[entrypoint] Installing extra packages: ${OPENCLAW_DOCKER_APT_PACKAGES}"
    apt-get update -qq
    # shellcheck disable=SC2086
    apt-get install -y --no-install-recommends ${OPENCLAW_DOCKER_APT_PACKAGES}
    rm -rf /var/lib/apt/lists/*
    echo "[entrypoint] Extra packages installed."
fi

# ── 5. Generate OpenClaw config from env vars ───────────────
echo "[entrypoint] Running configure.js..."
node /opt/kali-openclaw/configure.js

# ── 6. Set up nginx basic auth ──────────────────────────────
AUTH_USERNAME="${AUTH_USERNAME:-admin}"
AUTH_PASSWORD="${AUTH_PASSWORD:-}"

if [ -n "${AUTH_PASSWORD}" ]; then
    echo "[entrypoint] Setting up basic auth for user: ${AUTH_USERNAME}"
    htpasswd -cb /etc/nginx/.htpasswd "${AUTH_USERNAME}" "${AUTH_PASSWORD}"
else
    echo "[entrypoint] WARNING: No AUTH_PASSWORD set — web UI is unprotected!"
    rm -f /etc/nginx/.htpasswd
fi

# ── 7. Start background services ────────────────────────────
# Redis (if installed)
if command -v redis-server &>/dev/null; then
    redis-server --daemonize yes --save "" --appendonly no \
        >> /data/logs/redis.log 2>&1 || true
    echo "[entrypoint] Redis started"
fi

# ── 8. Start nginx ──────────────────────────────────────────
echo "[entrypoint] Starting nginx..."
nginx

# ── 9. Print toolkit summary ────────────────────────────────
TOOL_COUNT=$(find /opt/toolkit/tools -maxdepth 1 -mindepth 1 -type d 2>/dev/null | wc -l)
GO_COUNT=$(find /opt/toolkit/go/bin -type f 2>/dev/null | wc -l)
echo ""
echo "=========================================="
echo "  OpenClaw Toolkit Ready"
echo "  Git repos:     ${TOOL_COUNT}"
echo "  Go binaries:   ${GO_COUNT}"
echo "  OpenClaw UI:   http://0.0.0.0:8080"
echo "=========================================="
echo ""

# ── 10. Start OpenClaw gateway (foreground) ─────────────────
echo "[entrypoint] Starting OpenClaw gateway on :18789..."
exec openclaw-gateway \
    --config /data/.openclaw/config.json \
    --host 0.0.0.0 \
    --port 18789
