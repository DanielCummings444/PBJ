"""Standalone CLI for the PBIP Analyzer.

Usage:
    python -m pbip_analyzer.cli <project_path> [--format json|text|whitepaper] [--output <file>]
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

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


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Analyze a Power BI Project (PBIP) directory",
    )
    parser.add_argument(
        "project_path",
        help="Path to the PBIP project root directory",
    )
    parser.add_argument(
        "--format", "-f",
        choices=["json", "text", "whitepaper"],
        default="whitepaper",
        help="Output format (default: whitepaper)",
    )
    parser.add_argument(
        "--output", "-o",
        help="Save output to file instead of printing to stdout",
    )

    args = parser.parse_args()
    root = Path(args.project_path).expanduser().resolve()

    if not root.is_dir():
        print(f"Error: Directory not found: {root}", file=sys.stderr)
        sys.exit(1)

    # Parse the project
    result = parse_project(root)

    if result.model is None and result.report is None:
        print(
            "Error: No SemanticModel or Report folder found in the "
            f"project directory: {root}",
            file=sys.stderr,
        )
        sys.exit(1)

    # Run all analyzers
    analyze_model(result)
    analyze_dax(result)
    analyze_relationships(result)
    analyze_report(result)
    analyze_performance(result)

    # Generate output
    if args.format == "json":
        output = export_quantitative_json(result)
    elif args.format == "text":
        output = format_quantitative_text(result)
    else:
        output = generate_whitepaper(result)

    if args.output:
        out_path = Path(args.output).expanduser().resolve()
        out_path.parent.mkdir(parents=True, exist_ok=True)
        out_path.write_text(output, encoding="utf-8")
        print(f"Report saved to: {out_path}", file=sys.stderr)
    else:
        print(output)


if __name__ == "__main__":
    main()
