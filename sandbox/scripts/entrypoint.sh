#!/usr/bin/env bash
set -e

# ──────────────────────────────────────────────
# PBIP Analyzer MCP Server — Entrypoint
# ──────────────────────────────────────────────

if [ -t 0 ] && [ "$1" = "bash" ]; then
    echo ""
    echo "  PBIP Analyzer MCP Server"
    echo "  ────────────────────────"
    echo "  Tools:  analyze_pbip, analyze_pbip_report, list_pbip_metrics"
    echo "  Data:   /data/projects (mount PBIP projects here)"
    echo "  Output: /data/reports  (generated reports)"
    echo ""
fi

exec "$@"
