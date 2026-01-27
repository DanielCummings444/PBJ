#!/usr/bin/env bash
set -e

# ──────────────────────────────────────────────
# PBJ CLI-VM Entrypoint
# ──────────────────────────────────────────────

# Print a welcome banner on interactive sessions
if [ -t 0 ]; then
    cat <<'BANNER'

  ╔═══════════════════════════════════════════╗
  ║          PBJ CLI-VM  •  Ready             ║
  ╚═══════════════════════════════════════════╝

  Installed tool categories:
    • System    : vim, nano, htop, tmux, tree, fzf
    • Network   : curl, wget, httpie, nmap, dig, mtr
    • Data      : jq, yq, csvkit, sqlite3
    • DevOps    : docker, kubectl, terraform, aws
    • VCS       : git, git-lfs, gh
    • Languages : python3, node (22.x)
    • Search    : ripgrep (rg), ag, fzf

  Workspace mounted at /workspace
  Run 'toolbox' to list all available CLI tools.

BANNER
fi

# Source any custom rc files users may have mounted in
if [ -f /workspace/.cli-vmrc ]; then
    # shellcheck disable=SC1091
    source /workspace/.cli-vmrc
fi

# Execute the command passed to the container (default: bash)
exec "$@"
