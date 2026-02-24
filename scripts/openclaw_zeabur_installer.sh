#!/usr/bin/env bash
#===============================================================================
#
#   ██████╗ ██████╗ ███████╗███╗   ██╗ ██████╗██╗      █████╗ ██╗    ██╗
#  ██╔═══██╗██╔══██╗██╔════╝████╗  ██║██╔════╝██║     ██╔══██╗██║    ██║
#  ██║   ██║██████╔╝█████╗  ██╔██╗ ██║██║     ██║     ███████║██║ █╗ ██║
#  ██║   ██║██╔═══╝ ██╔══╝  ██║╚██╗██║██║     ██║     ██╔══██║██║███╗██║
#  ╚██████╔╝██║     ███████╗██║ ╚████║╚██████╗███████╗██║  ██║╚███╔███╔╝
#   ╚═════╝ ╚═╝     ╚══════╝╚═╝  ╚═══╝ ╚═════╝╚══════╝╚═╝  ╚═╝ ╚══╝╚══╝
#
#   OPENCLAW QUANT + HACKER TOOLKIT — ZEABUR VPS EDITION
#   Version:  3.0-zeabur
#   Target:   Ubuntu/Kali on Zeabur VPS (container or VM mode)
#   Tools:    232+ across 16 categories
#
#   Usage:
#     chmod +x openclaw_zeabur_installer.sh
#     sudo ./openclaw_zeabur_installer.sh                  # Full install
#     sudo ./openclaw_zeabur_installer.sh --phase 10       # Single phase
#     sudo ./openclaw_zeabur_installer.sh --from 5         # Resume from phase 5
#     sudo ./openclaw_zeabur_installer.sh --list           # List phases
#     sudo ./openclaw_zeabur_installer.sh --verify         # Verify only
#     sudo ./openclaw_zeabur_installer.sh --minimal        # Core tools only
#
#   Environment Variables (set before running):
#     ZEABUR_DATA_DIR    — persistent volume mount (default: /data)
#     OPENCLAW_PORT      — port OpenClaw listens on (default: 8080)
#     SKIP_DOCKER        — set to "yes" to skip Docker tools
#     SKIP_GPU           — set to "yes" to skip GPU/heavy ML libs
#     DOCKER_BUILD       — set to "yes" when running inside docker build
#
#===============================================================================
set -uo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# ZEABUR + OPENCLAW CONFIGURATION
# ─────────────────────────────────────────────────────────────────────────────
readonly ZEABUR_DATA="${ZEABUR_DATA_DIR:-/data}"
readonly TOOLKIT_DIR="${TOOLKIT_DIR:-/opt/toolkit}"
readonly PERSIST_TOOLS="${TOOLKIT_DIR}/tools"
readonly PERSIST_VENVS="${TOOLKIT_DIR}/venvs"
readonly PERSIST_GO="${TOOLKIT_DIR}/go"
readonly PERSIST_CARGO="${TOOLKIT_DIR}/cargo"
readonly PERSIST_FOUNDRY="${TOOLKIT_DIR}/foundry"
readonly PERSIST_NPM="${TOOLKIT_DIR}/npm-global"
readonly PERSIST_COMPOSE="${TOOLKIT_DIR}/stacks"
readonly PERSIST_LOGS="${TOOLKIT_DIR}/logs"
readonly PERSIST_CONFIG="${TOOLKIT_DIR}/config"

# OpenClaw integration
readonly OPENCLAW_PORT="${OPENCLAW_PORT:-8080}"
readonly OPENCLAW_HOME="${ZEABUR_DATA}/openclaw"

# Tool versions
readonly GO_VERSION="1.22.5"
readonly NODE_VERSION="22"
readonly GHIDRA_VERSION="11.1.2"
readonly GHIDRA_DATE="20240709"
readonly TERRAFORM_VERSION="1.9.0"
readonly ELK_VERSION="8.13.0"
readonly SCRIPT_VERSION="3.0-zeabur"

# ─────────────────────────────────────────────────────────────────────────────
# COLORS
# ─────────────────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
NC='\033[0m'

# ─────────────────────────────────────────────────────────────────────────────
# ENVIRONMENT DETECTION FLAGS — set during Phase 0
# ─────────────────────────────────────────────────────────────────────────────
IS_CONTAINER=false
HAS_DOCKER=false
HAS_SYSTEMD=false
SKIP_HEAVY=false
IS_MINIMAL=false
IS_DOCKER_BUILD="${DOCKER_BUILD:-no}"
SKIP_DOCKER_FLAG="${SKIP_DOCKER:-no}"
SKIP_GPU_FLAG="${SKIP_GPU:-no}"

# ─────────────────────────────────────────────────────────────────────────────
# LOGGING
# ─────────────────────────────────────────────────────────────────────────────
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a

# Create directories
mkdir -p "$TOOLKIT_DIR" "$PERSIST_TOOLS" "$PERSIST_VENVS" "$PERSIST_GO" \
         "$PERSIST_CARGO" "$PERSIST_FOUNDRY" "$PERSIST_NPM" "$PERSIST_COMPOSE" \
         "$PERSIST_LOGS" "$PERSIST_CONFIG" 2>/dev/null || true

mkdir -p "$OPENCLAW_HOME" 2>/dev/null || true

LOG_FILE="${PERSIST_LOGS}/install_$(date +%Y%m%d_%H%M%S).log"
FAIL_LOG="${PERSIST_LOGS}/failed_installs.txt"
PASS_LOG="${PERSIST_LOGS}/passed_installs.txt"
touch "$LOG_FILE" "$FAIL_LOG" "$PASS_LOG"

TOTAL_INSTALLED=0
TOTAL_FAILED=0
TOTAL_SKIPPED=0
PHASE_START_TIME=0
GLOBAL_START=0

log()      { echo -e "$1" | tee -a "$LOG_FILE"; }
info()     { log "${GREEN}[+]${NC} $1"; }
warn()     { log "${YELLOW}[!]${NC} $1"; }
fail()     { log "${RED}[x]${NC} $1"; }
header()   { log "\n${CYAN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; \
             log "${CYAN}${BOLD}  $1${NC}"; \
             log "${CYAN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"; }
start_phase() { PHASE_START_TIME=$(date +%s); header "PHASE $1: $2"; }
end_phase() {
    local elapsed=$(( $(date +%s) - PHASE_START_TIME ))
    info "Phase $1 complete in $(( elapsed / 60 ))m $(( elapsed % 60 ))s"
    echo ""
}

# ─────────────────────────────────────────────────────────────────────────────
# SAFE INSTALL HELPERS
# ─────────────────────────────────────────────────────────────────────────────
apt_install() {
    local name="$1"; shift
    log "${BLUE}[apt]${NC} $name"
    if apt-get install -y "$@" >> "$LOG_FILE" 2>&1; then
        info "$name"; echo "$name" >> "$PASS_LOG"; ((TOTAL_INSTALLED++)); return 0
    else
        fail "$name (apt)"; echo "$name" >> "$FAIL_LOG"; ((TOTAL_FAILED++)); return 1
    fi
}

pip_install() {
    local name="$1"; shift
    log "${MAGENTA}[pip]${NC} $name"
    if pip3 install --break-system-packages "$@" >> "$LOG_FILE" 2>&1; then
        info "$name"; echo "$name" >> "$PASS_LOG"; ((TOTAL_INSTALLED++)); return 0
    else
        fail "$name (pip)"; echo "$name" >> "$FAIL_LOG"; ((TOTAL_FAILED++)); return 1
    fi
}

go_install() {
    local name="$1"; local pkg="$2"
    log "${BLUE}[go]${NC}  $name"
    if GOPATH="$PERSIST_GO" /usr/local/go/bin/go install "$pkg" >> "$LOG_FILE" 2>&1; then
        info "$name"; echo "$name" >> "$PASS_LOG"; ((TOTAL_INSTALLED++)); return 0
    else
        fail "$name (go)"; echo "$name" >> "$FAIL_LOG"; ((TOTAL_FAILED++)); return 1
    fi
}

npm_install() {
    local name="$1"; shift
    log "${BLUE}[npm]${NC} $name"
    if npm install -g --prefix "$PERSIST_NPM" "$@" >> "$LOG_FILE" 2>&1; then
        info "$name"; echo "$name" >> "$PASS_LOG"; ((TOTAL_INSTALLED++)); return 0
    else
        fail "$name (npm)"; echo "$name" >> "$FAIL_LOG"; ((TOTAL_FAILED++)); return 1
    fi
}

gem_install() {
    local name="$1"; shift
    log "${BLUE}[gem]${NC} $name"
    if gem install "$@" >> "$LOG_FILE" 2>&1; then
        info "$name"; echo "$name" >> "$PASS_LOG"; ((TOTAL_INSTALLED++)); return 0
    else
        fail "$name (gem)"; echo "$name" >> "$FAIL_LOG"; ((TOTAL_FAILED++)); return 1
    fi
}

cargo_install() {
    local name="$1"; local pkg="$2"
    log "${BLUE}[cargo]${NC} $name"
    if CARGO_HOME="$PERSIST_CARGO" "$PERSIST_CARGO/bin/cargo" install "$pkg" >> "$LOG_FILE" 2>&1 || \
       "$HOME/.cargo/bin/cargo" install "$pkg" >> "$LOG_FILE" 2>&1; then
        info "$name"; echo "$name" >> "$PASS_LOG"; ((TOTAL_INSTALLED++)); return 0
    else
        fail "$name (cargo)"; echo "$name" >> "$FAIL_LOG"; ((TOTAL_FAILED++)); return 1
    fi
}

git_clone() {
    local name="$1"; local url="$2"; local dest="$PERSIST_TOOLS/$name"
    log "${BLUE}[git]${NC} $name"
    if [[ -d "$dest" ]]; then
        warn "$name — already cloned"; ((TOTAL_SKIPPED++)); return 0
    fi
    if git clone --depth 1 "$url" "$dest" >> "$LOG_FILE" 2>&1; then
        info "$name"; echo "$name" >> "$PASS_LOG"; ((TOTAL_INSTALLED++)); return 0
    else
        fail "$name (git)"; echo "$name" >> "$FAIL_LOG"; ((TOTAL_FAILED++)); return 1
    fi
}

docker_pull() {
    local name="$1"; local image="$2"
    if ! $HAS_DOCKER; then
        warn "$name — Docker unavailable, skipping"; ((TOTAL_SKIPPED++)); return 1
    fi
    log "${BLUE}[docker]${NC} $name"
    if docker pull "$image" >> "$LOG_FILE" 2>&1; then
        info "$name"; echo "$name" >> "$PASS_LOG"; ((TOTAL_INSTALLED++)); return 0
    else
        fail "$name (docker)"; echo "$name" >> "$FAIL_LOG"; ((TOTAL_FAILED++)); return 1
    fi
}

run_safe() {
    local name="$1"; local cmd="$2"
    log "${BLUE}[cmd]${NC} $name"
    if eval "$cmd" >> "$LOG_FILE" 2>&1; then
        info "$name"; echo "$name" >> "$PASS_LOG"; ((TOTAL_INSTALLED++)); return 0
    else
        fail "$name"; echo "$name" >> "$FAIL_LOG"; ((TOTAL_FAILED++)); return 1
    fi
}

cmd_exists() { command -v "$1" &>/dev/null; }

skip_if_exists() {
    local name="$1"; local cmd="$2"
    if cmd_exists "$cmd"; then
        warn "$name — already installed"; ((TOTAL_SKIPPED++)); return 0
    fi
    return 1
}

# Zeabur-safe service management
svc_enable() {
    local svc="$1"
    if $HAS_SYSTEMD; then
        systemctl enable "$svc" >> "$LOG_FILE" 2>&1 || true
        systemctl start "$svc" >> "$LOG_FILE" 2>&1 || true
    elif [[ "$IS_DOCKER_BUILD" == "yes" ]]; then
        # During docker build, skip service starts
        warn "Docker build mode — skipping service start for $svc"
    else
        service "$svc" start >> "$LOG_FILE" 2>&1 || \
        warn "Cannot start $svc — no systemd and service command failed"
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# PATH SETUP
# ─────────────────────────────────────────────────────────────────────────────
setup_paths() {
    export PATH="$PATH:/usr/local/go/bin:${PERSIST_GO}/bin:${PERSIST_CARGO}/bin:${PERSIST_FOUNDRY}/bin:${PERSIST_NPM}/bin:$HOME/.cargo/bin:$HOME/.local/bin:$HOME/.foundry/bin"
    export GOPATH="$PERSIST_GO"
    export CARGO_HOME="$PERSIST_CARGO"
    export npm_config_prefix="$PERSIST_NPM"
    export TOOLS_DIR="$PERSIST_TOOLS"
}
setup_paths

# ─────────────────────────────────────────────────────────────────────────────
# ARGUMENT PARSING
# ─────────────────────────────────────────────────────────────────────────────
PHASE_FILTER=""
PHASE_FROM=""
RUN_VERIFY_ONLY=false
LIST_ONLY=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --phase)    PHASE_FILTER="$2"; shift 2 ;;
        --from)     PHASE_FROM="$2"; shift 2 ;;
        --verify)   RUN_VERIFY_ONLY=true; shift ;;
        --list)     LIST_ONLY=true; shift ;;
        --minimal)  IS_MINIMAL=true; shift ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --phase N    Install only phase N"
            echo "  --from N     Resume from phase N"
            echo "  --verify     Verification only (no installs)"
            echo "  --list       List all phases"
            echo "  --minimal    Core tools only"
            echo "  -h, --help   This help"
            exit 0
            ;;
        *) echo "Unknown: $1 (use -h)"; exit 1 ;;
    esac
done

should_run() {
    local phase="$1"
    if $IS_MINIMAL; then
        case "$phase" in
            0|1|2|3|4|9|10|15|16) ;;
            *) return 1 ;;
        esac
    fi
    if [[ -n "$PHASE_FILTER" ]]; then [[ "$PHASE_FILTER" == "$phase" ]]
    elif [[ -n "$PHASE_FROM" ]]; then [[ "$phase" -ge "$PHASE_FROM" ]]
    else return 0; fi
}

if $LIST_ONLY; then
    echo ""
    echo "  Phase  0: Environment Detection & Pre-Flight"
    echo "  Phase  1: System Update & Core Build Dependencies"
    echo "  Phase  2: Programming Languages & Runtimes"
    echo "  Phase  3: Offensive Security & Pentesting (~35 tools)"
    echo "  Phase  4: OSINT & Reconnaissance (~25 tools)"
    echo "  Phase  5: Digital Forensics & Reverse Engineering (~20 tools)"
    echo "  Phase  6: Web Application Security (~12 tools)"
    echo "  Phase  7: Cloud & Container Security (~10 tools)"
    echo "  Phase  8: Evasion, Wireless & IoT (~8 tools)"
    echo "  Phase  9: Data Science & Analytics (~30 libraries)"
    echo "  Phase 10: Quantitative Finance & Trading (~35 libraries)"
    echo "  Phase 11: Blockchain & DeFi Security (~14 tools)"
    echo "  Phase 12: Network Infrastructure & Monitoring (~15 tools)"
    echo "  Phase 13: Automation, Orchestration & AI Frameworks (~15 tools)"
    echo "  Phase 14: Operational Security (~10 tools)"
    echo "  Phase 15: Configuration & Environment Setup"
    echo "  Phase 16: Final Verification & Report"
    echo ""
    echo "  --minimal runs: 0,1,2,3,4,9,10,15,16 only"
    exit 0
fi

SKIP_TO_VERIFY=false
if $RUN_VERIFY_ONLY; then SKIP_TO_VERIFY=true; fi

# ═══════════════════════════════════════════════════════════════════════════════
#  PHASE 0: ENVIRONMENT DETECTION & PRE-FLIGHT
# ═══════════════════════════════════════════════════════════════════════════════
if ! $SKIP_TO_VERIFY && should_run 0; then
start_phase 0 "Environment Detection & Pre-Flight"
GLOBAL_START=$(date +%s)

echo -e "${BOLD}"
echo "================================================================"
echo "  OPENCLAW QUANT + HACKER TOOLKIT v${SCRIPT_VERSION}"
echo "  232+ tools across 16 phases"
echo "================================================================"
echo -e "${NC}"

# Detect container
if [[ "$IS_DOCKER_BUILD" == "yes" ]] || [[ -f /.dockerenv ]] || \
   grep -qE '(docker|lxc|kubepods|containerd)' /proc/1/cgroup 2>/dev/null; then
    IS_CONTAINER=true
    log "  Mode:        CONTAINER"
else
    IS_CONTAINER=false
    log "  Mode:        FULL VM"
fi

# Check systemd
if pidof systemd &>/dev/null || [[ "$(cat /proc/1/comm 2>/dev/null)" == "systemd" ]]; then
    HAS_SYSTEMD=true
else
    HAS_SYSTEMD=false
fi

# Docker: always skip during docker build (no Docker-in-Docker)
if [[ "$IS_DOCKER_BUILD" == "yes" ]] || [[ "$SKIP_DOCKER_FLAG" == "yes" ]]; then
    HAS_DOCKER=false
    log "  Docker:      SKIPPED (build mode)"
elif cmd_exists docker && docker info &>/dev/null 2>&1; then
    HAS_DOCKER=true
    log "  Docker:      available"
else
    HAS_DOCKER=false
    log "  Docker:      unavailable"
fi

# System specs
ARCH=$(uname -m)
CPU_COUNT=$(nproc 2>/dev/null || echo "1")
RAM_MB=$(free -m 2>/dev/null | awk '/^Mem:/{print $2}' || echo "0")

log "  Arch:        $ARCH"
log "  CPUs:        $CPU_COUNT"
log "  RAM:         ${RAM_MB} MB"
log "  Toolkit:     $TOOLKIT_DIR"
log "  Log:         $LOG_FILE"

if [[ "$RAM_MB" -gt 0 && "$RAM_MB" -lt 4096 ]]; then
    SKIP_HEAVY=true
    warn "Low RAM (${RAM_MB} MB) — skipping heavy ML libs"
fi

if [[ "$SKIP_GPU_FLAG" == "yes" ]]; then
    SKIP_HEAVY=true
fi

> "$FAIL_LOG"
> "$PASS_LOG"
setup_paths

end_phase 0
fi

# ═══════════════════════════════════════════════════════════════════════════════
#  PHASE 1: SYSTEM UPDATE & CORE BUILD DEPENDENCIES
# ═══════════════════════════════════════════════════════════════════════════════
if ! $SKIP_TO_VERIFY && should_run 1; then
start_phase 1 "System Update & Core Build Dependencies"

log "Updating package lists..."
apt-get update -y >> "$LOG_FILE" 2>&1
apt-get upgrade -y >> "$LOG_FILE" 2>&1 || true

apt_install "Core Build Tools" \
    build-essential gcc g++ make cmake \
    autoconf automake libtool pkg-config \
    git git-lfs curl wget \
    unzip zip p7zip-full \
    software-properties-common \
    apt-transport-https ca-certificates \
    gnupg lsb-release

apt_install "Development Libraries" \
    libssl-dev libffi-dev \
    libxml2-dev libxslt1-dev \
    zlib1g-dev libbz2-dev \
    libreadline-dev libsqlite3-dev \
    libncursesw5-dev libgdbm-dev liblzma-dev \
    tk-dev uuid-dev \
    libpcap-dev libpq-dev \
    libfreetype6-dev libjpeg-dev libpng-dev \
    libcurl4-openssl-dev \
    libmagic-dev libyaml-dev \
    libev-dev libsodium-dev

apt_install "System Utilities" \
    jq tree htop \
    tmux screen \
    net-tools dnsutils \
    whois traceroute mtr \
    strace ltrace \
    sysstat \
    ncat socat \
    xxd dos2unix \
    pv pigz rsync bc \
    sshpass

apt_install "Extra Utils" iotop hexedit figlet 2>/dev/null || true

end_phase 1
fi

# ═══════════════════════════════════════════════════════════════════════════════
#  PHASE 2: PROGRAMMING LANGUAGES & RUNTIMES
# ═══════════════════════════════════════════════════════════════════════════════
if ! $SKIP_TO_VERIFY && should_run 2; then
start_phase 2 "Programming Languages & Runtimes"

# ── Python ───────────────────────────────────────────────────────────────────
log "Installing Python..."
apt_install "Python 3 (core)" \
    python3 python3-pip python3-venv python3-dev \
    python3-setuptools python3-wheel

apt_install "pipx" pipx || pip3 install --break-system-packages pipx >> "$LOG_FILE" 2>&1 || true
pip3 install --break-system-packages --upgrade pip setuptools wheel >> "$LOG_FILE" 2>&1
info "pip upgraded"

# ── Node.js ──────────────────────────────────────────────────────────────────
if skip_if_exists "Node.js" "node"; then true; else
    log "Installing Node.js ${NODE_VERSION}.x..."
    curl -fsSL "https://deb.nodesource.com/setup_${NODE_VERSION}.x" | bash - >> "$LOG_FILE" 2>&1
    apt_install "Node.js" nodejs
fi
npm install -g npm@latest >> "$LOG_FILE" 2>&1 || true
npm_install "yarn + pnpm" yarn pnpm || true
npm config set prefix "$PERSIST_NPM" >> "$LOG_FILE" 2>&1 || true

# ── Go ───────────────────────────────────────────────────────────────────────
if skip_if_exists "Go" "/usr/local/go/bin/go"; then true; else
    log "Installing Go ${GO_VERSION}..."
    wget -q "https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz" -O /tmp/go.tar.gz
    rm -rf /usr/local/go
    tar -C /usr/local -xzf /tmp/go.tar.gz
    rm -f /tmp/go.tar.gz
    info "Go ${GO_VERSION}"
fi
export PATH="$PATH:/usr/local/go/bin:${PERSIST_GO}/bin"
export GOPATH="$PERSIST_GO"

# ── Rust ─────────────────────────────────────────────────────────────────────
if skip_if_exists "Rust" "rustc" || skip_if_exists "Rust" "${PERSIST_CARGO}/bin/rustc"; then true; else
    log "Installing Rust..."
    CARGO_HOME="$PERSIST_CARGO" RUSTUP_HOME="$PERSIST_CARGO" \
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y >> "$LOG_FILE" 2>&1
    info "Rust toolchain"
fi
export PATH="$PATH:${PERSIST_CARGO}/bin:$HOME/.cargo/bin"
source "$HOME/.cargo/env" 2>/dev/null || source "${PERSIST_CARGO}/env" 2>/dev/null || true

# ── Ruby ─────────────────────────────────────────────────────────────────────
apt_install "Ruby" ruby ruby-dev ruby-bundler

# ── R ────────────────────────────────────────────────────────────────────────
if ! $IS_MINIMAL; then
    apt_install "R" r-base r-base-dev || true
fi

# ── Java ─────────────────────────────────────────────────────────────────────
apt_install "Java (JDK)" default-jdk default-jre

end_phase 2
fi

# ═══════════════════════════════════════════════════════════════════════════════
#  PHASE 3: OFFENSIVE SECURITY & PENTESTING
# ═══════════════════════════════════════════════════════════════════════════════
if ! $SKIP_TO_VERIFY && should_run 3; then
start_phase 3 "Offensive Security & Pentesting (~35 tools)"

apt_install "Nmap"              nmap
apt_install "Masscan"           masscan
apt_install "SQLMap"            sqlmap
apt_install "Nikto"             nikto
apt_install "Aircrack-ng"       aircrack-ng
apt_install "Hashcat"           hashcat
apt_install "John the Ripper"   john
apt_install "Hydra"             hydra
apt_install "Medusa (brute)"    medusa

go_install "FFuf"       "github.com/ffuf/ffuf/v2@latest"
go_install "Gobuster"   "github.com/OJ/gobuster/v3@latest"
go_install "Chisel"     "github.com/jpillora/chisel@latest"
go_install "Kerbrute"   "github.com/ropnop/kerbrute@latest"

gem_install "WPScan"     wpscan
gem_install "Evil-WinRM"  evil-winrm

pip_install "Impacket"          impacket
pip_install "Certipy-AD"        certipy-ad
pip_install "Coercer"           coercer
pip_install "enum4linux-ng"     enum4linux-ng
pip_install "Dirsearch"         dirsearch
pip_install "BloodHound.py"     bloodhound
pip_install "CrackMapExec"      crackmapexec || pip_install "NetExec" netexec || true

cargo_install "RustScan" "rustscan" || \
    run_safe "RustScan (deb)" "wget -q https://github.com/RustScan/RustScan/releases/latest/download/rustscan_2.3.0_amd64.deb -O /tmp/rustscan.deb && dpkg -i /tmp/rustscan.deb" || true

apt_install "Feroxbuster" feroxbuster || \
    run_safe "Feroxbuster (curl)" "curl -sL https://raw.githubusercontent.com/epi052/feroxbuster/main/install-nix.sh | bash -s /usr/local/bin" || true

# Metasploit
if skip_if_exists "Metasploit" "msfconsole"; then true; else
    log "Installing Metasploit..."
    run_safe "Metasploit" \
        "curl https://raw.githubusercontent.com/rapid7/metasploit-omnibus/master/config/templates/metasploit-framework-wrappers/msfupdate.erb > /tmp/msfinstall && chmod 755 /tmp/msfinstall && /tmp/msfinstall"
fi

# Sliver C2
run_safe "Sliver C2" "curl https://sliver.sh/install | bash" || true

# Git repos
git_clone "Responder"    "https://github.com/lgandx/Responder.git"
git_clone "PowerSploit"  "https://github.com/PowerShellMafia/PowerSploit.git"
git_clone "Rubeus"       "https://github.com/GhostPack/Rubeus.git"
git_clone "mimikatz"     "https://github.com/gentilkiwi/mimikatz.git"
git_clone "BloodHound"   "https://github.com/BloodHoundAD/BloodHound.git"
git_clone "Havoc"        "https://github.com/HavocFramework/Havoc.git"
git_clone "Mythic"       "https://github.com/its-a-feature/Mythic.git"
git_clone "Villain"      "https://github.com/t3l3machus/Villain.git"
git_clone "Ligolo-ng"    "https://github.com/nicocha30/ligolo-ng.git"

end_phase 3
fi

# ═══════════════════════════════════════════════════════════════════════════════
#  PHASE 4: OSINT & RECONNAISSANCE
# ═══════════════════════════════════════════════════════════════════════════════
if ! $SKIP_TO_VERIFY && should_run 4; then
start_phase 4 "OSINT & Reconnaissance (~25 tools)"

pip_install "theHarvester"     theharvester
pip_install "Shodan CLI"       shodan
pip_install "Censys CLI"       censys
pip_install "Sherlock"         sherlock-project
pip_install "Holehe"           holehe
pip_install "Maigret"          maigret
pip_install "Instaloader"      instaloader
pip_install "snscrape"         snscrape
pip_install "h8mail"           h8mail
pip_install "CrossLinked"      crosslinked
pip_install "SpiderFoot"       spiderfoot
pip_install "Recon-ng"         recon-ng
pip_install "TruffleHog"       trufflehog
pip_install "dnsrecon"         dnsrecon
pip_install "GHunt"            ghunt

go_install "Amass"        "github.com/owasp-amass/amass/v4/...@master"
go_install "Subfinder"    "github.com/projectdiscovery/subfinder/v2/cmd/subfinder@latest"
go_install "httpx"        "github.com/projectdiscovery/httpx/cmd/httpx@latest"
go_install "Nuclei"       "github.com/projectdiscovery/nuclei/v3/cmd/nuclei@latest"
go_install "DNSx"         "github.com/projectdiscovery/dnsx/cmd/dnsx@latest"
go_install "waybackurls"  "github.com/tomnomnom/waybackurls@latest"
go_install "gau"          "github.com/lc/gau/v2/cmd/gau@latest"
go_install "PhoneInfoga"  "github.com/sundowndev/phoneinfoga/v2@latest"

apt_install "ExifTool" libimage-exiftool-perl

end_phase 4
fi

# ═══════════════════════════════════════════════════════════════════════════════
#  PHASE 5: DIGITAL FORENSICS & REVERSE ENGINEERING
# ═══════════════════════════════════════════════════════════════════════════════
if ! $SKIP_TO_VERIFY && should_run 5; then
start_phase 5 "Digital Forensics & Reverse Engineering (~20 tools)"

apt_install "Wireshark/tshark"  wireshark-common tshark
apt_install "tcpdump"           tcpdump
apt_install "Sleuth Kit"        sleuthkit
apt_install "Autopsy"           autopsy || true
apt_install "bulk_extractor"    bulk-extractor || true
apt_install "Foremost/Scalpel"  foremost scalpel || true
apt_install "ClamAV"            clamav clamav-daemon
apt_install "YARA"              yara
apt_install "Android Tools"     android-tools-adb android-tools-fastboot || true

pip_install "Volatility3"  volatility3
pip_install "angr"         angr
pip_install "Capstone"     capstone
pip_install "Unicorn"      unicorn
pip_install "pwntools"     pwntools
pip_install "Frida"        frida-tools
pip_install "MVT"          mvt
pip_install "FLOSS"        flare-floss || true

# Radare2
if skip_if_exists "Radare2" "r2"; then true; else
    run_safe "Radare2" "git clone --depth 1 https://github.com/radareorg/radare2.git /tmp/radare2 && cd /tmp/radare2 && sys/install.sh" || \
        apt_install "Radare2 (apt)" radare2
fi

# Ghidra
if [[ ! -d /opt/ghidra_* ]]; then
    run_safe "Ghidra" \
        "wget -q https://github.com/NationalSecurityAgency/ghidra/releases/download/Ghidra_${GHIDRA_VERSION}_build/ghidra_${GHIDRA_VERSION}_PUBLIC_${GHIDRA_DATE}.zip -O /tmp/ghidra.zip && \
         unzip -qo /tmp/ghidra.zip -d /opt && rm -f /tmp/ghidra.zip && \
         ln -sf /opt/ghidra_*/ghidraRun /usr/local/bin/ghidra" || true
else
    warn "Ghidra already installed"; ((TOTAL_SKIPPED++))
fi

end_phase 5
fi

# ═══════════════════════════════════════════════════════════════════════════════
#  PHASE 6: WEB APPLICATION SECURITY
# ═══════════════════════════════════════════════════════════════════════════════
if ! $SKIP_TO_VERIFY && should_run 6; then
start_phase 6 "Web Application Security (~12 tools)"

pip_install "mitmproxy"   mitmproxy
pip_install "wfuzz"       wfuzz
pip_install "Arjun"       arjun
pip_install "Droopescan"  droopescan

git_clone "XSStrike"     "https://github.com/s0md3v/XSStrike.git"
git_clone "NoSQLMap"     "https://github.com/codingo/NoSQLMap.git"
git_clone "jwt_tool"     "https://github.com/ticarpi/jwt_tool.git"
git_clone "GraphQLmap"   "https://github.com/swisskyrepo/GraphQLmap.git"
git_clone "ParamSpider"  "https://github.com/devanshbatham/ParamSpider.git"

[[ -f "$PERSIST_TOOLS/jwt_tool/requirements.txt" ]] && \
    pip3 install --break-system-packages -r "$PERSIST_TOOLS/jwt_tool/requirements.txt" >> "$LOG_FILE" 2>&1 || true

go_install "Kiterunner" "github.com/assetnote/kiterunner/cmd/kr@latest" || true

end_phase 6
fi

# ═══════════════════════════════════════════════════════════════════════════════
#  PHASE 7: CLOUD & CONTAINER SECURITY
# ═══════════════════════════════════════════════════════════════════════════════
if ! $SKIP_TO_VERIFY && should_run 7; then
start_phase 7 "Cloud & Container Security (~10 tools)"

pip_install "ScoutSuite"   scoutsuite
pip_install "Prowler"      prowler
pip_install "AWS CLI"      awscli
pip_install "Pacu"         pacu
pip_install "kube-hunter"  kube-hunter

run_safe "kubectl" \
    "curl -sLO 'https://dl.k8s.io/release/\$(curl -sL https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl' && \
     install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl && rm -f kubectl" || true

run_safe "CDK" \
    "wget -q https://github.com/cdk-team/CDK/releases/latest/download/cdk_linux_amd64 -O /usr/local/bin/cdk && chmod +x /usr/local/bin/cdk" || true

git_clone "cloud_enum"    "https://github.com/initstring/cloud_enum.git"
git_clone "enumerate-iam" "https://github.com/andresriancho/enumerate-iam.git"

end_phase 7
fi

# ═══════════════════════════════════════════════════════════════════════════════
#  PHASE 8: EVASION, WIRELESS & IoT
# ═══════════════════════════════════════════════════════════════════════════════
if ! $SKIP_TO_VERIFY && should_run 8; then
start_phase 8 "Evasion, Wireless & IoT (~8 tools)"

apt_install "Kismet"              kismet || true
apt_install "hcxdumptool/hcxtools" hcxdumptool hcxtools || true

pip_install "Donut (shellcode)" donut-shellcode || true

git_clone "Veil"       "https://github.com/Veil-Framework/Veil.git"
git_clone "ScareCrow"  "https://github.com/optiv/ScareCrow.git"
git_clone "Wifite2"    "https://github.com/derv82/wifite2.git"

end_phase 8
fi

# ═══════════════════════════════════════════════════════════════════════════════
#  PHASE 9: DATA SCIENCE & ANALYTICS
# ═══════════════════════════════════════════════════════════════════════════════
if ! $SKIP_TO_VERIFY && should_run 9; then
start_phase 9 "Data Science & Analytics (~30 libraries)"

pip_install "Core Data Science" \
    numpy scipy pandas \
    matplotlib seaborn plotly \
    scikit-learn \
    jupyterlab notebook ipywidgets ipykernel

pip_install "XGBoost"        xgboost
pip_install "LightGBM"       lightgbm
pip_install "CatBoost"       catboost
pip_install "SHAP"           shap
pip_install "Optuna"         optuna
pip_install "feature-engine" feature-engine
pip_install "hmmlearn"       hmmlearn

# PyTorch CPU
pip_install "PyTorch (CPU)" "torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cpu"

# TensorFlow — heavy, skip on low RAM
if $SKIP_HEAVY; then
    warn "Skipping TensorFlow (low RAM / SKIP_GPU)"; ((TOTAL_SKIPPED++))
else
    pip_install "TensorFlow" tensorflow
fi

pip_install "HuggingFace Transformers" transformers
pip_install "VADER Sentiment"          vaderSentiment
pip_install "newspaper3k"              newspaper3k

pip_install "DuckDB" duckdb

apt_install "Tesseract OCR" tesseract-ocr tesseract-ocr-eng
pip_install "pytesseract"   pytesseract

end_phase 9
fi

# ═══════════════════════════════════════════════════════════════════════════════
#  PHASE 10: QUANTITATIVE FINANCE & TRADING
# ═══════════════════════════════════════════════════════════════════════════════
if ! $SKIP_TO_VERIFY && should_run 10; then
start_phase 10 "Quantitative Finance & Trading (~35 libraries)"

pip_install "Exchange Connectors" \
    ccxt yfinance \
    polygon-api-client \
    binance-connector \
    python-okx \
    alpaca-trade-api \
    ib_insync \
    tardis-dev

pip_install "Social APIs" praw tweepy
pip_install "Backtrader"   backtrader
pip_install "vectorbt"     vectorbt
pip_install "bt"           bt
pip_install "Zipline"      zipline-reloaded || true

pip_install "Quant Analysis" \
    arch statsmodels linearmodels \
    empyrical-reloaded ffn \
    pandas-ta finta

pip_install "QuantLib"     QuantLib-Python
pip_install "pyfolio"      pyfolio-reloaded
pip_install "SEC EDGAR"    sec-edgar-downloader

# TA-Lib
log "Building TA-Lib C library..."
run_safe "TA-Lib (C)" \
    "wget -q https://github.com/TA-Lib/ta-lib/releases/download/v0.6.4/ta-lib-0.6.4-src.tar.gz -O /tmp/ta-lib.tar.gz && \
     cd /tmp && tar -xzf ta-lib.tar.gz && cd ta-lib-0.6.4 && \
     ./configure --prefix=/usr && make -j\$(nproc) && make install && ldconfig" || true
pip_install "TA-Lib (Python)" ta-lib || warn "TA-Lib Python wrapper failed — use pandas-ta instead"

pip_install "Stable-Baselines3" stable-baselines3
pip_install "Gymnasium"         gymnasium
pip_install "gym-anytrading"    gym-anytrading || true
pip_install "FinRL"             finrl || true

end_phase 10
fi

# ═══════════════════════════════════════════════════════════════════════════════
#  PHASE 11: BLOCKCHAIN & DeFi SECURITY
# ═══════════════════════════════════════════════════════════════════════════════
if ! $SKIP_TO_VERIFY && should_run 11; then
start_phase 11 "Blockchain & DeFi Security (~14 tools)"

run_safe "Foundry (install)" "FOUNDRY_DIR=${PERSIST_FOUNDRY} curl -L https://foundry.paradigm.xyz | bash"
export PATH="$PATH:${PERSIST_FOUNDRY}/bin:$HOME/.foundry/bin"
run_safe "Foundry (foundryup)" "foundryup" || true

pip_install "solc-select" solc-select
run_safe "solc (latest)" "solc-select install latest && solc-select use latest" || true

pip_install "Slither"     slither-analyzer
pip_install "Mythril"     mythril

run_safe "Echidna" \
    "wget -q https://github.com/crytic/echidna/releases/latest/download/echidna-Linux.zip -O /tmp/echidna.zip && \
     unzip -qo /tmp/echidna.zip -d /tmp/echidna && \
     find /tmp/echidna -name 'echidna' -type f -exec mv {} /usr/local/bin/echidna \; && \
     chmod +x /usr/local/bin/echidna" || true

pip_install "web3.py"      web3
pip_install "Dune Client"  dune-client
pip_install "Flashbots"    flashbots || true
pip_install "eth-brownie"  eth-brownie || true
pip_install "eth-ape"      eth-ape || true

npm_install "Hardhat"   hardhat
npm_install "ethers.js" ethers

end_phase 11
fi

# ═══════════════════════════════════════════════════════════════════════════════
#  PHASE 12: NETWORK INFRASTRUCTURE & MONITORING
# ═══════════════════════════════════════════════════════════════════════════════
if ! $SKIP_TO_VERIFY && should_run 12; then
start_phase 12 "Network Infrastructure & Monitoring"

apt_install "Suricata"      suricata || true
apt_install "Redis"         redis-server redis-tools
apt_install "WireGuard"     wireguard wireguard-tools || true
apt_install "Nginx"         nginx
apt_install "Fail2Ban"      fail2ban
apt_install "rkhunter"      rkhunter chkrootkit || true
apt_install "auditd"        auditd || true
apt_install "Zeek"          zeek || true

run_safe "Tailscale" "curl -fsSL https://tailscale.com/install.sh | sh" || true

end_phase 12
fi

# ═══════════════════════════════════════════════════════════════════════════════
#  PHASE 13: AUTOMATION, ORCHESTRATION & AI FRAMEWORKS
# ═══════════════════════════════════════════════════════════════════════════════
if ! $SKIP_TO_VERIFY && should_run 13; then
start_phase 13 "Automation, Orchestration & AI Frameworks"

pip_install "Prefect"       prefect
pip_install "Celery"        "celery[redis]"
pip_install "Ansible"       ansible
pip_install "LangChain"     "langchain langchain-community langchain-core"
pip_install "CrewAI"        crewai
pip_install "AutoGen"       pyautogen || true
pip_install "OpenAI SDK"    openai
pip_install "Anthropic SDK" anthropic
pip_install "Ollama Python" ollama

# Terraform
if skip_if_exists "Terraform" "terraform"; then true; else
    run_safe "Terraform" \
        "wget -q https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_amd64.zip -O /tmp/terraform.zip && \
         unzip -qo /tmp/terraform.zip -d /usr/local/bin && rm -f /tmp/terraform.zip"
fi

# Ollama
run_safe "Ollama" "curl -fsSL https://ollama.com/install.sh | sh" || true

end_phase 13
fi

# ═══════════════════════════════════════════════════════════════════════════════
#  PHASE 14: OPERATIONAL SECURITY
# ═══════════════════════════════════════════════════════════════════════════════
if ! $SKIP_TO_VERIFY && should_run 14; then
start_phase 14 "Operational Security"

apt_install "GPG2"          gnupg2
apt_install "Tor"           tor torsocks
apt_install "ProxyChains"   proxychains4
apt_install "BleachBit"     bleachbit || true
apt_install "age"           age || go_install "age" "filippo.io/age/cmd/...@latest"

end_phase 14
fi

# ═══════════════════════════════════════════════════════════════════════════════
#  PHASE 15: CONFIGURATION & ENVIRONMENT SETUP
# ═══════════════════════════════════════════════════════════════════════════════
if ! $SKIP_TO_VERIFY && should_run 15; then
start_phase 15 "Configuration & Environment Setup"

# ── Global environment profile ───────────────────────────────────────────────
cat > /etc/profile.d/agent-toolkit.sh << ENVEOF
# OpenClaw Agent Toolkit Environment
export PATH="\$PATH:/usr/local/go/bin:${PERSIST_GO}/bin:${PERSIST_CARGO}/bin:${PERSIST_FOUNDRY}/bin:${PERSIST_NPM}/bin:\$HOME/.cargo/bin:\$HOME/.local/bin:\$HOME/.foundry/bin"
export GOPATH="${PERSIST_GO}"
export CARGO_HOME="${PERSIST_CARGO}"
export TOOLS_DIR="${PERSIST_TOOLS}"
export npm_config_prefix="${PERSIST_NPM}"
export TOOLKIT_DIR="${TOOLKIT_DIR}"

# Source API keys from persistent config or env file
[[ -f "${PERSIST_CONFIG}/.env" ]] && source "${PERSIST_CONFIG}/.env"
[[ -f "\$HOME/.env" ]] && source "\$HOME/.env"

# Aliases
alias ll='ls -alFh'
alias ports='ss -tulpn'
alias myip='curl -s ifconfig.me'
alias scan='nmap -sC -sV'
alias serve='python3 -m http.server'
alias jlab='jupyter lab --ip=0.0.0.0 --no-browser --allow-root --port=8888'
alias msfstart='msfdb init && msfconsole'
ENVEOF

source /etc/profile.d/agent-toolkit.sh 2>/dev/null || true
info "Environment profile configured"

# ── OpenClaw tools manifest ──────────────────────────────────────────────────
mkdir -p "$OPENCLAW_HOME" 2>/dev/null || true
cat > "${TOOLKIT_DIR}/openclaw_tools.json" << TOOLEOF
{
  "agent_name": "OpenClaw Quant-Hacker Agent",
  "version": "${SCRIPT_VERSION}",
  "installed_at": "$(date -Iseconds)",
  "toolkit_directory": "${TOOLKIT_DIR}",
  "tools_directory": "${PERSIST_TOOLS}",
  "go_binaries": "${PERSIST_GO}/bin",
  "npm_binaries": "${PERSIST_NPM}/bin",
  "cargo_binaries": "${PERSIST_CARGO}/bin",
  "capabilities": {
    "quant_trading": ["ccxt","yfinance","backtrader","vectorbt","QuantLib","statsmodels","pandas-ta","stable-baselines3"],
    "offensive_security": ["nmap","masscan","sqlmap","hydra","metasploit","ffuf","gobuster","nuclei","impacket","certipy"],
    "osint": ["amass","subfinder","sherlock","shodan","theharvester","nuclei","httpx","trufflehog","maigret"],
    "forensics": ["volatility3","wireshark","radare2","ghidra","angr","frida","yara","pwntools"],
    "blockchain": ["foundry","slither","mythril","web3","echidna"],
    "data_science": ["numpy","pandas","scikit-learn","pytorch","xgboost","transformers","jupyter"],
    "ai_frameworks": ["langchain","crewai","openai","anthropic","ollama"]
  }
}
TOOLEOF
info "Tools manifest created"

# ── Cleanup ──────────────────────────────────────────────────────────────────
log "Cleaning up..."
apt-get autoremove -y >> "$LOG_FILE" 2>&1 || true
apt-get clean >> "$LOG_FILE" 2>&1 || true
rm -rf /tmp/go.tar.gz /tmp/radare2 /tmp/ta-lib* /tmp/ghidra.zip \
       /tmp/echidna* /tmp/msfinstall /tmp/terraform.zip /tmp/rustscan.deb 2>/dev/null
rm -rf /var/lib/apt/lists/* 2>/dev/null || true

end_phase 15
fi

# ═══════════════════════════════════════════════════════════════════════════════
#  PHASE 16: FINAL VERIFICATION & REPORT
# ═══════════════════════════════════════════════════════════════════════════════
if should_run 16 || $SKIP_TO_VERIFY; then
header "PHASE 16: Final Verification Report"

setup_paths
source /etc/profile.d/agent-toolkit.sh 2>/dev/null || true
source "$HOME/.cargo/env" 2>/dev/null || true

V_PASS=0; V_FAIL=0

v() {
    local name="$1"; local cmd="$2"
    if eval "$cmd" &>/dev/null; then
        echo -e "  ${GREEN}+${NC} $name"; ((V_PASS++))
    else
        echo -e "  ${RED}x${NC} $name"; ((V_FAIL++))
    fi
}

vp() {
    local name="$1"; local mod="$2"
    if python3 -c "import $mod" &>/dev/null; then
        echo -e "  ${GREEN}+${NC} $name"; ((V_PASS++))
    else
        echo -e "  ${RED}x${NC} $name"; ((V_FAIL++))
    fi
}

echo -e "\n${BOLD}-- Languages & Runtimes --${NC}"
v "Python 3"      "python3 --version"
v "pip3"          "pip3 --version"
v "Node.js"       "node --version"
v "Go"            "go version || /usr/local/go/bin/go version"
v "Rust"          "rustc --version || ${PERSIST_CARGO}/bin/rustc --version"
v "Ruby"          "ruby --version"
v "Java"          "java --version"

echo -e "\n${BOLD}-- Offensive Security --${NC}"
v "Nmap"          "which nmap"
v "Masscan"       "which masscan"
v "SQLMap"        "which sqlmap"
v "Nikto"         "which nikto"
v "Hydra"         "which hydra"
v "Hashcat"       "which hashcat"
v "John"          "which john"
v "Metasploit"    "which msfconsole"
v "FFuf"          "which ffuf || test -f ${PERSIST_GO}/bin/ffuf"
v "Gobuster"      "which gobuster || test -f ${PERSIST_GO}/bin/gobuster"
v "Chisel"        "which chisel || test -f ${PERSIST_GO}/bin/chisel"
v "Feroxbuster"   "which feroxbuster"
vp "Impacket"     "impacket"
vp "Certipy"      "certipy"
vp "BloodHound.py" "bloodhound"

echo -e "\n${BOLD}-- OSINT & Recon --${NC}"
v "Amass"         "which amass || test -f ${PERSIST_GO}/bin/amass"
v "Subfinder"     "which subfinder || test -f ${PERSIST_GO}/bin/subfinder"
v "httpx"         "which httpx || test -f ${PERSIST_GO}/bin/httpx"
v "Nuclei"        "which nuclei || test -f ${PERSIST_GO}/bin/nuclei"
v "DNSx"          "which dnsx || test -f ${PERSIST_GO}/bin/dnsx"
v "ExifTool"      "which exiftool"
vp "Shodan"       "shodan"
vp "Sherlock"     "sherlock"
vp "TruffleHog"   "trufflehog"

echo -e "\n${BOLD}-- Forensics & RE --${NC}"
v "tshark"        "which tshark"
v "tcpdump"       "which tcpdump"
v "ClamAV"        "which clamscan"
v "YARA"          "which yara"
v "Radare2"       "which r2"
v "Ghidra"        "test -f /usr/local/bin/ghidra || test -d /opt/ghidra_*"
vp "Volatility3"  "volatility3"
vp "angr"         "angr"
vp "Frida"        "frida"
vp "pwntools"     "pwn"

echo -e "\n${BOLD}-- Data Science --${NC}"
vp "NumPy"        "numpy"
vp "Pandas"       "pandas"
vp "scikit-learn" "sklearn"
vp "PyTorch"      "torch"
vp "XGBoost"      "xgboost"
vp "JupyterLab"   "jupyterlab"
vp "DuckDB"       "duckdb"

echo -e "\n${BOLD}-- Quant Finance --${NC}"
vp "ccxt"         "ccxt"
vp "yfinance"     "yfinance"
vp "Backtrader"   "backtrader"
vp "vectorbt"     "vectorbt"
vp "QuantLib"     "QuantLib"
vp "statsmodels"  "statsmodels"
vp "arch (GARCH)" "arch"
vp "pandas-ta"    "pandas_ta"
vp "Optuna"       "optuna"

echo -e "\n${BOLD}-- Blockchain & DeFi --${NC}"
v "Foundry"       "which forge || test -f ${PERSIST_FOUNDRY}/bin/forge || test -f $HOME/.foundry/bin/forge"
vp "web3.py"      "web3"
vp "Slither"      "slither"
v "Echidna"       "which echidna"
vp "Dune Client"  "dune_client"

echo -e "\n${BOLD}-- Infrastructure --${NC}"
v "Redis"         "which redis-cli"
v "Nginx"         "which nginx"
v "Terraform"     "which terraform"
v "Fail2Ban"      "which fail2ban-client"
vp "Ansible"      "ansible"
vp "Celery"       "celery"
vp "Prefect"      "prefect"

echo -e "\n${BOLD}-- AI & Agent Frameworks --${NC}"
vp "LangChain"    "langchain"
vp "CrewAI"       "crewai"
vp "OpenAI SDK"   "openai"
vp "Anthropic SDK" "anthropic"
v "Ollama"        "which ollama"

echo -e "\n${BOLD}-- OPSEC --${NC}"
v "GPG"           "which gpg"
v "Tor"           "which tor"
v "ProxyChains"   "which proxychains4"

echo -e "\n${BOLD}-- Toolkit Files --${NC}"
v "Tools Manifest"       "test -f ${TOOLKIT_DIR}/openclaw_tools.json"
v "Environment Profile"  "test -f /etc/profile.d/agent-toolkit.sh"

echo -e "\n${BOLD}-- Git-Cloned Repos --${NC}"
for repo in Responder PowerSploit mimikatz BloodHound Havoc Mythic Villain XSStrike jwt_tool; do
    v "$repo" "test -d ${PERSIST_TOOLS}/$repo"
done

# ── Summary ──────────────────────────────────────────────────────────────────
if ! $SKIP_TO_VERIFY; then
    GLOBAL_END=$(date +%s)
    TOTAL_ELAPSED=$(( GLOBAL_END - GLOBAL_START ))
    TOTAL_MINS=$(( TOTAL_ELAPSED / 60 ))
    TOTAL_SECS=$(( TOTAL_ELAPSED % 60 ))
fi

echo ""
echo -e "${BOLD}================================================================${NC}"
echo -e "${BOLD}  OPENCLAW TOOLKIT — INSTALLATION COMPLETE${NC}"
echo -e "${BOLD}================================================================${NC}"
echo -e "  Verification:  ${GREEN}${V_PASS} passed${NC}  |  ${RED}${V_FAIL} failed${NC}"
if ! $SKIP_TO_VERIFY; then
echo -e "  Installed:     ${GREEN}${TOTAL_INSTALLED}${NC}  |  Failed: ${RED}${TOTAL_FAILED}${NC}  |  Skipped: ${YELLOW}${TOTAL_SKIPPED}${NC}"
echo -e "  Time:          ${TOTAL_MINS}m ${TOTAL_SECS}s"
fi
echo -e "  Toolkit:       ${TOOLKIT_DIR}"
echo -e "  Log:           ${LOG_FILE}"
echo -e "${BOLD}================================================================${NC}"

if [[ -f "$FAIL_LOG" ]] && [[ -s "$FAIL_LOG" ]]; then
    echo ""
    echo -e "${RED}${BOLD}Failed installs:${NC}"
    cat "$FAIL_LOG" | while read -r line; do echo -e "  ${RED}-${NC} $line"; done
fi

fi

echo ""
log "Script finished at $(date)"
