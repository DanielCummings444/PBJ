# Kali-OpenClaw

OpenClaw AI assistant running on Kali Linux. Fully environment-driven — no interactive setup needed. Deploy to Zeabur, any VPS, or run locally with Docker.

## Quick Start (Local)

```bash
# 1. Clone
git clone https://github.com/YOUR_USERNAME/kali-openclaw.git
cd kali-openclaw

# 2. Configure
cp .env.example .env
# Edit .env — at minimum set ANTHROPIC_API_KEY and AUTH_PASSWORD

# 3. Run
docker compose up -d

# 4. Open http://localhost:8080 (login: admin / your AUTH_PASSWORD)
```

## Deploy to Zeabur

### Option A: Deploy from GitHub (recommended)

1. Push this repo to your GitHub account
2. Go to [Zeabur Dashboard](https://dash.zeabur.com) → **Create Project** → pick a region
3. **Deploy New Service** → **GitHub** → select your `kali-openclaw` repo
4. Zeabur auto-detects the Dockerfile and builds it
5. Configure in the service settings:

| Setting | Value |
|---|---|
| **Environment Variables** | |
| `ANTHROPIC_API_KEY` | Your API key |
| `AUTH_PASSWORD` | A strong password |
| `PORT` | `8080` |
| **Ports** | |
| Port `8080`, type `HTTP` | |
| **Volumes** | |
| Mount path: `/data` | |

6. Go to **Networking** → **Generate Domain** to get a `.zeabur.app` URL
7. Visit your domain and log in with `admin` / your password

### Option B: Zeabur Template (one-click)

1. Edit `zeabur-template.yaml` — replace `YOUR_GITHUB_USERNAME` with your username
2. Deploy:
   ```bash
   npx zeabur@latest template deploy -f zeabur-template.yaml
   ```

### Option C: Zeabur CLI

```bash
# Install Zeabur CLI
npm install -g zeabur

# Login
zeabur auth login

# Deploy from current directory
zeabur deploy
```

## Architecture

```
┌────────────────────────────────────────────┐
│  Docker container (kali-openclaw)          │
│                                            │
│  Kali Linux Rolling                        │
│  ┌──────────┐ :8080  ┌─────────────────┐  │
│  │  nginx    │──────→ │  openclaw       │  │
│  │  (basic   │ proxy  │  gateway        │  │
│  │   auth)   │ :18789 │  :18789         │  │
│  └──────────┘        └─────────────────┘  │
│                                            │
│  /data/.openclaw/  ← config & state        │
│  /data/workspace/  ← project files         │
│                                            │
│  entrypoint.sh                             │
│    1. install extra apt packages           │
│    2. configure.js (env vars → json)       │
│    3. setup nginx auth                     │
│    4. start nginx + openclaw gateway       │
└────────────────────────────────────────────┘
```

## Environment Variables

### AI Providers (at least one required)

| Variable | Description |
|---|---|
| `ANTHROPIC_API_KEY` | Anthropic (Claude) — highest priority |
| `OPENAI_API_KEY` | OpenAI (GPT) |
| `OPENROUTER_API_KEY` | OpenRouter |
| `GEMINI_API_KEY` | Google Gemini |
| `XAI_API_KEY` | xAI (Grok) |
| `GROQ_API_KEY` | Groq |
| `MISTRAL_API_KEY` | Mistral |
| `OLLAMA_BASE_URL` | Ollama local (e.g. `http://host.docker.internal:11434`) |

### Auth & Gateway

| Variable | Default | Description |
|---|---|---|
| `AUTH_PASSWORD` | *(none)* | Web UI password. If unset, UI is open |
| `AUTH_USERNAME` | `admin` | Web UI username |
| `OPENCLAW_GATEWAY_TOKEN` | *(auto)* | Gateway API token. Auto-generated if unset |
| `PORT` | `8080` | External port |

### Messaging Channels

| Variable | Description |
|---|---|
| `TELEGRAM_BOT_TOKEN` | Telegram bot token from @BotFather |
| `TELEGRAM_DM_POLICY` | `pairing` / `allowlist` / `open` |
| `DISCORD_BOT_TOKEN` | Discord bot token |

### Extras

| Variable | Description |
|---|---|
| `OPENCLAW_DOCKER_APT_PACKAGES` | Space-separated apt packages to install at startup (e.g. `nmap sqlmap nikto`) |
| `OPENCLAW_PRIMARY_MODEL` | Override model (e.g. `anthropic/claude-sonnet-4-5-20250929`) |

See `.env.example` for the full list.

## Adding Kali Tools

**At build time** (baked into image) — edit the Dockerfile:

```dockerfile
# Uncomment or add:
RUN apt-get update && apt-get install -y nmap sqlmap nikto metasploit-framework && rm -rf /var/lib/apt/lists/*
```

**At runtime** (installed on each restart) — set the env var:

```
OPENCLAW_DOCKER_APT_PACKAGES=nmap sqlmap nikto
```

## Files

```
.
├── Dockerfile              # Multi-stage: build OpenClaw on Kali Linux
├── docker-compose.yml      # Local dev / docker compose up
├── nginx/
│   └── default.conf        # Reverse proxy with optional basic auth
├── scripts/
│   ├── configure.js        # Env vars → openclaw.json config
│   └── entrypoint.sh       # Container entrypoint
├── zeabur-template.yaml    # Zeabur one-click deploy template
├── .env.example            # All supported env vars
├── .dockerignore
├── .gitignore
└── README.md
```

## License

MIT
