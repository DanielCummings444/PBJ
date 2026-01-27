#!/usr/bin/env bash
# ──────────────────────────────────────────────
# run.sh — Build, run, and manage the PBIP Analyzer sandbox
# ──────────────────────────────────────────────
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
    cat <<EOF
Usage: $(basename "$0") <command> [args...]

Commands:
  build                  Build the Docker image
  mcp                    Start the MCP server (stdio mode)
  analyze <path>         Run CLI analysis (whitepaper format)
  analyze-json <path>    Run CLI analysis (JSON format)
  analyze-text <path>    Run CLI analysis (text format)
  sample                 Run analysis on the included sample project
  shell                  Open a bash shell in the container
  help                   Show this help

MCP Integration:
  Copy sandbox/mcp_config.json into your Claude Desktop or
  MCP client configuration to use the analyzer as an MCP tool.

Examples:
  $(basename "$0") build
  $(basename "$0") sample
  $(basename "$0") analyze /path/to/MyProject
  $(basename "$0") analyze-json /path/to/MyProject > report.json
EOF
}

cmd_build() {
    echo "Building PBIP Analyzer image..."
    docker compose -f "$SCRIPT_DIR/docker-compose.yml" build
    echo "Done."
}

cmd_mcp() {
    docker compose -f "$SCRIPT_DIR/docker-compose.yml" run --rm -i \
        pbip-analyzer python -m pbip_analyzer.server
}

cmd_analyze() {
    local project_path="${1:?Error: project_path is required}"
    local format="${2:-whitepaper}"
    local output="${3:-}"

    local args=("python" "-m" "pbip_analyzer.cli" "$project_path" "--format" "$format")
    if [ -n "$output" ]; then
        args+=("--output" "$output")
    fi

    docker compose -f "$SCRIPT_DIR/docker-compose.yml" run --rm \
        pbip-analyzer "${args[@]}"
}

cmd_sample() {
    echo "Running analysis on sample AdventureWorks project..."
    docker compose -f "$SCRIPT_DIR/docker-compose.yml" run --rm \
        pbip-analyzer python -m pbip_analyzer.cli \
        /data/samples \
        --format whitepaper \
        --output /data/reports/sample-report.md
    echo ""
    echo "Whitepaper report saved to: sandbox/reports/sample-report.md"
    echo ""
    echo "Also generating JSON output..."
    docker compose -f "$SCRIPT_DIR/docker-compose.yml" run --rm \
        pbip-analyzer python -m pbip_analyzer.cli \
        /data/samples \
        --format json \
        --output /data/reports/sample-report.json
    echo "JSON report saved to: sandbox/reports/sample-report.json"
}

cmd_shell() {
    docker compose -f "$SCRIPT_DIR/docker-compose.yml" run --rm \
        pbip-analyzer bash
}

# ── Main ──────────────────────────────────────
if [ $# -eq 0 ]; then
    usage
    exit 1
fi

case "$1" in
    build)         cmd_build ;;
    mcp)           cmd_mcp ;;
    analyze)       shift; cmd_analyze "$@" ;;
    analyze-json)  shift; cmd_analyze "${1:?path required}" "json" "${2:-}" ;;
    analyze-text)  shift; cmd_analyze "${1:?path required}" "text" "${2:-}" ;;
    sample)        cmd_sample ;;
    shell)         cmd_shell ;;
    help|-h|--help) usage ;;
    *)
        echo "Unknown command: $1"
        usage
        exit 1
        ;;
esac
