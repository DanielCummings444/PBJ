"""MCP server for the PBIP Analyzer.

Exposes three tools via the Model Context Protocol:

  1. analyze_pbip       — Full analysis returning quantitative JSON
  2. analyze_pbip_report — Full analysis returning a whitepaper Markdown report
  3. list_pbip_metrics   — Quick metrics-only scan (no findings detail)
"""

from __future__ import annotations

import json
import logging
import os
from pathlib import Path

from mcp.server import Server
from mcp.server.stdio import stdio_server
from mcp.types import TextContent, Tool

from pbip_analyzer.analyzers.dax_analyzer import analyze_dax
from pbip_analyzer.analyzers.model_analyzer import analyze_model
from pbip_analyzer.analyzers.performance_analyzer import analyze_performance
from pbip_analyzer.analyzers.relationship_analyzer import analyze_relationships
from pbip_analyzer.analyzers.report_analyzer import analyze_report
from pbip_analyzer.parsers.pbip_parser import parse_project
from pbip_analyzer.reporters.quantitative import (
    export_quantitative_json,
    format_quantitative_text,
)
from pbip_analyzer.reporters.whitepaper import generate_whitepaper

logger = logging.getLogger("pbip-analyzer-mcp")

app = Server("pbip-analyzer")


def _run_full_analysis(project_path: str):
    """Parse and run all analyzers on a PBIP project."""
    root = Path(project_path).expanduser().resolve()
    if not root.is_dir():
        raise FileNotFoundError(f"Directory not found: {root}")

    result = parse_project(root)

    # Run all analyzers
    analyze_model(result)
    analyze_dax(result)
    analyze_relationships(result)
    analyze_report(result)
    analyze_performance(result)

    return result


# ── Tool definitions ──────────────────────────────────────────────────

TOOLS = [
    Tool(
        name="analyze_pbip",
        description=(
            "Analyze a Power BI Project (PBIP) directory and return "
            "quantitative findings as structured JSON. Examines model "
            "structure, DAX quality, relationships, report design, and "
            "performance characteristics."
        ),
        inputSchema={
            "type": "object",
            "properties": {
                "project_path": {
                    "type": "string",
                    "description": (
                        "Absolute path to the PBIP project root directory "
                        "containing *.SemanticModel and/or *.Report folders."
                    ),
                },
                "output_format": {
                    "type": "string",
                    "enum": ["json", "text"],
                    "default": "json",
                    "description": (
                        "Output format: 'json' for structured data, "
                        "'text' for formatted plain text."
                    ),
                },
            },
            "required": ["project_path"],
        },
    ),
    Tool(
        name="analyze_pbip_report",
        description=(
            "Analyze a Power BI Project (PBIP) directory and return a "
            "professional whitepaper-style Markdown report. Includes "
            "executive summary, quantitative overview, detailed findings "
            "with recommendations, and a prioritized action plan."
        ),
        inputSchema={
            "type": "object",
            "properties": {
                "project_path": {
                    "type": "string",
                    "description": (
                        "Absolute path to the PBIP project root directory."
                    ),
                },
                "save_to": {
                    "type": "string",
                    "description": (
                        "Optional file path to save the Markdown report. "
                        "If omitted, the report is returned as text."
                    ),
                },
            },
            "required": ["project_path"],
        },
    ),
    Tool(
        name="list_pbip_metrics",
        description=(
            "Quick scan of a PBIP project returning only quantitative "
            "metrics (table count, column count, measure count, etc.) "
            "without detailed findings."
        ),
        inputSchema={
            "type": "object",
            "properties": {
                "project_path": {
                    "type": "string",
                    "description": (
                        "Absolute path to the PBIP project root directory."
                    ),
                },
            },
            "required": ["project_path"],
        },
    ),
]


@app.list_tools()
async def list_tools():
    return TOOLS


@app.call_tool()
async def call_tool(name: str, arguments: dict):
    try:
        if name == "analyze_pbip":
            return await _handle_analyze(arguments)
        elif name == "analyze_pbip_report":
            return await _handle_report(arguments)
        elif name == "list_pbip_metrics":
            return await _handle_metrics(arguments)
        else:
            return [TextContent(type="text", text=f"Unknown tool: {name}")]
    except FileNotFoundError as e:
        return [TextContent(type="text", text=f"Error: {e}")]
    except Exception as e:
        logger.exception("Tool error")
        return [TextContent(type="text", text=f"Analysis error: {e}")]


async def _handle_analyze(arguments: dict):
    project_path = arguments["project_path"]
    output_format = arguments.get("output_format", "json")

    result = _run_full_analysis(project_path)

    if output_format == "text":
        text = format_quantitative_text(result)
    else:
        text = export_quantitative_json(result)

    return [TextContent(type="text", text=text)]


async def _handle_report(arguments: dict):
    project_path = arguments["project_path"]
    save_to = arguments.get("save_to")

    result = _run_full_analysis(project_path)
    report_md = generate_whitepaper(result)

    if save_to:
        out_path = Path(save_to).expanduser().resolve()
        out_path.parent.mkdir(parents=True, exist_ok=True)
        out_path.write_text(report_md, encoding="utf-8")
        return [TextContent(
            type="text",
            text=f"Report saved to: {out_path}\n\n{report_md}",
        )]

    return [TextContent(type="text", text=report_md)]


async def _handle_metrics(arguments: dict):
    project_path = arguments["project_path"]
    result = _run_full_analysis(project_path)

    metrics = [m.to_dict() for m in result.metrics]
    text = json.dumps({"project": project_path, "metrics": metrics}, indent=2)

    return [TextContent(type="text", text=text)]


async def main():
    """Run the MCP server over stdio."""
    logger.info("Starting PBIP Analyzer MCP server")
    async with stdio_server() as (read_stream, write_stream):
        await app.run(read_stream, write_stream, app.create_initialization_options())


if __name__ == "__main__":
    import asyncio

    logging.basicConfig(level=logging.INFO)
    asyncio.run(main())
