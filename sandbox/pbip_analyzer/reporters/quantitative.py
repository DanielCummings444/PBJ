"""Quantitative findings reporter.

Produces structured JSON and formatted text summaries of all
quantitative metrics and findings counts from a completed analysis.
"""

from __future__ import annotations

import json
from typing import Any

from pbip_analyzer.models.findings import AnalysisResult, Severity


def generate_quantitative_report(result: AnalysisResult) -> dict[str, Any]:
    """Return a structured dict of quantitative findings."""
    summary = result.summary_counts()
    by_category = result.findings_by_category()

    report: dict[str, Any] = {
        "project": result.project_path,
        "overview": {
            "total_findings": len(result.findings),
            "by_severity": summary,
            "total_metrics": len(result.metrics),
        },
        "metrics": [m.to_dict() for m in result.metrics],
        "findings_by_category": {},
        "severity_distribution": summary,
    }

    for cat, findings in sorted(by_category.items()):
        report["findings_by_category"][cat] = {
            "count": len(findings),
            "critical": sum(
                1 for f in findings if f.severity == Severity.CRITICAL
            ),
            "high": sum(
                1 for f in findings if f.severity == Severity.HIGH
            ),
            "medium": sum(
                1 for f in findings if f.severity == Severity.MEDIUM
            ),
            "low": sum(
                1 for f in findings if f.severity == Severity.LOW
            ),
            "findings": [f.to_dict() for f in findings],
        }

    return report


def format_quantitative_text(result: AnalysisResult) -> str:
    """Return a human-readable text summary of quantitative findings."""
    lines: list[str] = []
    summary = result.summary_counts()

    lines.append("=" * 70)
    lines.append("  QUANTITATIVE ANALYSIS REPORT")
    lines.append(f"  Project: {result.project_path}")
    lines.append("=" * 70)
    lines.append("")

    # ── Severity Summary ──────────────────────────────────────────────
    lines.append("FINDINGS SUMMARY")
    lines.append("-" * 40)
    total = len(result.findings)
    lines.append(f"  Total findings:  {total}")
    for sev in Severity:
        count = summary.get(sev.value, 0)
        bar = _bar(count, total)
        lines.append(f"  {sev.value.upper():<12s} {count:>4d}  {bar}")
    lines.append("")

    # ── Metrics Table ─────────────────────────────────────────────────
    lines.append("METRICS")
    lines.append("-" * 70)
    lines.append(f"  {'Metric':<45s} {'Value':>10s}  {'Status':<10s}")
    lines.append(f"  {'─' * 45} {'─' * 10}  {'─' * 10}")
    for m in result.metrics:
        val = str(m.value)
        if m.unit:
            val = f"{m.value}{m.unit}"
        status = m.status.upper() if m.status else ""
        lines.append(f"  {m.name:<45s} {val:>10s}  {status:<10s}")
    lines.append("")

    # ── Category Breakdown ────────────────────────────────────────────
    by_cat = result.findings_by_category()
    lines.append("FINDINGS BY CATEGORY")
    lines.append("-" * 70)
    for cat in sorted(by_cat.keys()):
        findings = by_cat[cat]
        lines.append(f"\n  [{cat}] — {len(findings)} finding(s)")
        for f in findings:
            sev_tag = f"[{f.severity.value.upper()}]"
            lines.append(f"    {sev_tag:<12s} {f.id}: {f.title}")
    lines.append("")

    lines.append("=" * 70)
    return "\n".join(lines)


def export_quantitative_json(result: AnalysisResult) -> str:
    """Return a pretty-printed JSON string."""
    return json.dumps(generate_quantitative_report(result), indent=2)


def _bar(count: int, total: int, width: int = 20) -> str:
    if total == 0:
        return ""
    filled = round(count / total * width)
    return "█" * filled + "░" * (width - filled)
