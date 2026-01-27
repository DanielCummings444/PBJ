#!/usr/bin/env bash
# ──────────────────────────────────────────────
# toolbox — list all available CLI tools
# ──────────────────────────────────────────────
set -e

bold="\033[1m"
dim="\033[2m"
reset="\033[0m"

check() {
    if command -v "$1" &>/dev/null; then
        local ver
        ver=$("$1" --version 2>/dev/null | head -1 || echo "installed")
        printf "  %-18s %s\n" "$1" "$ver"
    fi
}

section() {
    echo ""
    echo -e "${bold}$1${reset}"
    echo -e "${dim}$(printf '─%.0s' $(seq 1 40))${reset}"
}

echo ""
echo -e "${bold}PBJ CLI-VM — Installed Tools${reset}"

section "Editors"
check vim
check nano

section "File & Text Processing"
check jq
check yq
check csvkit
check sed
check awk
check rg
check ag
check fzf
check tree
check file
check zip
check unzip

section "Networking"
check curl
check wget
check http
check ssh
check nmap
check nc
check socat
check dig
check ping
check traceroute
check mtr
check tcpdump
check whois

section "Version Control"
check git
check git-lfs
check gh

section "Languages & Runtimes"
check python3
check pip3
check node
check npm

section "DevOps & Cloud"
check docker
check kubectl
check terraform
check aws

section "Database Clients"
check psql
check mysql
check redis-cli
check sqlite3

section "System & Process"
check htop
check tmux
check screen
check lsof
check strace
check bc

echo ""
