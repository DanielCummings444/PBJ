# OpenClaw Quant + Hacker Toolkit

OpenClaw AI assistant running on Kali Linux with **232+ tools pre-installed** across 16 categories: offensive security, OSINT, forensics, quantitative finance, blockchain, data science, and more.

**Plug and play** — deploy to Zeabur, enter your API keys, done.

## Quick Start (Zeabur — Recommended)

1. Push this repo to your GitHub account
2. Go to [Zeabur Dashboard](https://dash.zeabur.com) > **Create Project** > pick a region
3. **Deploy New Service** > **GitHub** > select this repo
4. Zeabur auto-detects the Dockerfile and builds it (the build installs all 232+ tools)
5. Add a **Volume** mounted at `/data`
6. Set **Environment Variables**:

| Variable | Required | Description |
|---|---|---|
| `ANTHROPIC_API_KEY` | Yes | Your Anthropic (Claude) API key |
| `AUTH_PASSWORD` | Yes | Password for web UI login |
| `PORT` | No | External port (default: `8080`) |

7. Go to **Networking** > **Generate Domain** to get your `.zeabur.app` URL
8. Visit your domain and log in with `admin` / your password

All 232+ tools are baked into the Docker image at build time. No waiting for installs on every restart.

## Quick Start (Local Docker)

```bash
# 1. Clone
git clone https://github.com/DanielCummings444/PBJ.git
cd PBJ

# 2. Configure
cp .env.example .env
# Edit .env — set ANTHROPIC_API_KEY and AUTH_PASSWORD at minimum

# 3. Build & run (first build takes a while — installs all tools)
docker compose up -d

# 4. Open http://localhost:8080
```

## One-Click Zeabur Template

```bash
npx zeabur@latest template deploy -f zeabur-template.yaml
```

## What's Included (232+ Tools)

| Category | Tools |
|---|---|
| **Offensive Security** (~35) | nmap, masscan, sqlmap, nikto, hydra, hashcat, john, metasploit, ffuf, gobuster, chisel, impacket, certipy, bloodhound, sliver, responder, mimikatz, and more |
| **OSINT & Recon** (~25) | amass, subfinder, httpx, nuclei, sherlock, shodan, theharvester, maigret, trufflehog, censys, recon-ng, spiderfoot, and more |
| **Forensics & RE** (~20) | volatility3, wireshark, radare2, ghidra, angr, frida, yara, pwntools, sleuthkit, clamav, and more |
| **Web App Security** (~12) | mitmproxy, wfuzz, arjun, xsstrike, jwt_tool, graphqlmap, paramspider, and more |
| **Cloud & Container** (~10) | scoutsuite, prowler, awscli, pacu, kubectl, trivy, kube-hunter, and more |
| **Data Science** (~30) | numpy, pandas, scikit-learn, pytorch, xgboost, lightgbm, catboost, transformers, jupyterlab, and more |
| **Quant Finance** (~35) | ccxt, yfinance, backtrader, vectorbt, QuantLib, statsmodels, pandas-ta, ta-lib, stable-baselines3, gymnasium, and more |
| **Blockchain & DeFi** (~14) | foundry, slither, mythril, echidna, web3.py, hardhat, ethers.js, and more |
| **AI Frameworks** (~15) | langchain, crewai, openai, anthropic, ollama, ansible, prefect, celery, and more |
| **OPSEC** (~10) | tor, proxychains, gpg, age, and more |
| **Languages** | Python 3, Node.js 20, Go, Rust, Ruby, Java |

## Architecture

```
+--------------------------------------------+
|  Docker container (openclaw-toolkit)       |
|                                            |
|  Kali Linux Rolling                        |
|  +----------+ :8080  +-----------------+  |
|  |  nginx    |------->|  openclaw       |  |
|  |  (basic   | proxy  |  gateway        |  |
|  |   auth)   | :18789 |  :18789        |  |
|  +----------+        +-----------------+  |
|                                            |
|  /opt/toolkit/  <- 232+ tools (baked in)   |
|  /data/.openclaw/  <- config & state       |
|  /data/workspace/  <- project files        |
|                                            |
|  entrypoint.sh                             |
|    1. source toolkit environment           |
|    2. write API keys from env vars         |
|    3. configure.js (env vars -> json)      |
|    4. setup nginx auth                     |
|    5. start redis + nginx                  |
|    6. start openclaw gateway               |
+--------------------------------------------+
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

### Auth & Gateway

| Variable | Default | Description |
|---|---|---|
| `AUTH_PASSWORD` | *(none)* | Web UI password |
| `AUTH_USERNAME` | `admin` | Web UI username |
| `PORT` | `8080` | External port |

### Trading & Market Data

| Variable | Description |
|---|---|
| `ALPACA_API_KEY` / `ALPACA_SECRET_KEY` | Alpaca trading |
| `BINANCE_API_KEY` / `BINANCE_SECRET_KEY` | Binance |
| `OKX_API_KEY` / `OKX_SECRET_KEY` / `OKX_PASSPHRASE` | OKX |
| `POLYGON_API_KEY` | Polygon.io market data |

### OSINT & Recon

| Variable | Description |
|---|---|
| `SHODAN_API_KEY` | Shodan |
| `CENSYS_API_ID` / `CENSYS_API_SECRET` | Censys |
| `VT_API_KEY` | VirusTotal |

### Blockchain

| Variable | Description |
|---|---|
| `INFURA_PROJECT_ID` | Infura Ethereum RPC |
| `ALCHEMY_API_KEY` | Alchemy |
| `ETHERSCAN_API_KEY` | Etherscan |
| `DUNE_API_KEY` | Dune Analytics |

### Notifications

| Variable | Description |
|---|---|
| `TELEGRAM_BOT_TOKEN` / `TELEGRAM_CHAT_ID` | Telegram alerts |
| `DISCORD_WEBHOOK_URL` | Discord alerts |
| `SLACK_WEBHOOK_URL` | Slack alerts |

See `.env.example` for the full list.

## Files

```
.
├── Dockerfile                              # Builds all 232+ tools into the image
├── docker-compose.yml                      # Local dev
├── nginx/
│   └── default.conf                        # Reverse proxy with auth + Jupyter
├── scripts/
│   ├── openclaw_zeabur_installer.sh        # Full 16-phase toolkit installer
│   ├── configure.js                        # Env vars -> openclaw config.json
│   └── entrypoint.sh                       # Container startup
├── zeabur-template.yaml                    # Zeabur one-click deploy template
├── .env.example                            # All supported env vars
├── .dockerignore
├── .gitignore
└── README.md
```

## License

MIT
