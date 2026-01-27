"""Whitepaper-style report generator.

Produces a professional, multi-section Markdown document suitable for
stakeholder review.  The report follows a structure inspired by
technical whitepapers:

  1. Executive Summary
  2. Methodology
  3. Quantitative Overview
  4. Detailed Findings (grouped by category)
  5. Recommendations & Action Plan
  6. Appendix — Full Metrics
"""

from __future__ import annotations

import datetime
from typing import Any

from pbip_analyzer.models.findings import (
    AnalysisResult,
    Category,
    Finding,
    Severity,
)


_SEVERITY_EMOJI = {
    Severity.CRITICAL: "🔴",
    Severity.HIGH: "🟠",
    Severity.MEDIUM: "🟡",
    Severity.LOW: "🔵",
    Severity.INFO: "⚪",
}

_SEVERITY_ORDER = [
    Severity.CRITICAL,
    Severity.HIGH,
    Severity.MEDIUM,
    Severity.LOW,
    Severity.INFO,
]


def generate_whitepaper(result: AnalysisResult) -> str:
    """Return a Markdown whitepaper report."""
    sections: list[str] = []

    sections.append(_title_page(result))
    sections.append(_executive_summary(result))
    sections.append(_methodology())
    sections.append(_quantitative_overview(result))
    sections.append(_detailed_findings(result))
    sections.append(_recommendations(result))
    sections.append(_appendix_metrics(result))
    sections.append(_appendix_all_findings(result))

    return "\n\n---\n\n".join(sections) + "\n"


# ── Sections ──────────────────────────────────────────────────────────


def _title_page(result: AnalysisResult) -> str:
    now = datetime.datetime.now(datetime.timezone.utc).strftime(
        "%B %d, %Y"
    )
    model_name = result.model.name if result.model else "Unknown"
    return f"""# Power BI Project Analysis Report

**Project:** `{result.project_path}`
**Model:** {model_name}
**Generated:** {now}
**Tool:** PBJ PBIP Analyzer v1.0

---

> This report presents a comprehensive analysis of the Power BI
> Project (PBIP), covering data model structure, DAX quality,
> relationship design, report layout, and performance characteristics.
> Each finding includes a severity rating, description, and
> actionable recommendation."""


def _executive_summary(result: AnalysisResult) -> str:
    counts = result.summary_counts()
    total = len(result.findings)
    critical = counts.get("critical", 0)
    high = counts.get("high", 0)

    # Determine overall health
    if critical > 0:
        health = "Critical — immediate action required"
    elif high > 2:
        health = "At Risk — significant issues identified"
    elif high > 0:
        health = "Fair — some issues need attention"
    else:
        health = "Good — minor improvements recommended"

    # Top categories
    by_cat = result.findings_by_category()
    top_cats = sorted(by_cat.items(), key=lambda x: len(x[1]), reverse=True)

    top_section = ""
    if top_cats:
        top_items = "\n".join(
            f"  - **{cat}**: {len(fs)} finding(s)"
            for cat, fs in top_cats[:5]
        )
        top_section = f"""
### Top Issue Areas

{top_items}
"""

    # Key metrics
    key_metrics = ""
    if result.metrics:
        rows = []
        for m in result.metrics[:8]:
            val = f"{m.value}{m.unit}" if m.unit else str(m.value)
            rows.append(f"| {m.name} | {val} | {m.status or '—'} |")
        metric_rows = "\n".join(rows)
        key_metrics = f"""
### Key Metrics

| Metric | Value | Status |
|--------|-------|--------|
{metric_rows}
"""

    return f"""## 1. Executive Summary

### Overall Health Assessment: **{health}**

This analysis identified **{total} findings** across the Power BI
project, including **{critical} critical** and **{high} high**
severity issues.
{top_section}{key_metrics}"""


def _methodology() -> str:
    return """## 2. Methodology

This analysis was performed using automated static analysis of the
Power BI Project (PBIP) source files. The following areas were
evaluated:

| Analysis Area | What Is Examined |
|---------------|------------------|
| **Model Structure** | Table count, column count, calculated columns, hidden items, documentation coverage |
| **DAX Quality** | Expression complexity, nesting depth, iterator usage, deprecated functions, formatting |
| **Relationships** | Cardinality, cross-filter direction, inactive relationships, circular paths, many-to-many |
| **Report Design** | Page count, visual density, visual types, overlapping visuals, bookmarks |
| **Performance** | Storage modes, composite model detection, iterator nesting, overall risk score |

### Severity Definitions

| Severity | Definition |
|----------|------------|
| 🔴 **Critical** | Causes incorrect results or will prevent deployment. Must fix. |
| 🟠 **High** | Significant performance or design risk. Should fix soon. |
| 🟡 **Medium** | Potential issue that may cause problems at scale. Plan to address. |
| 🔵 **Low** | Minor improvement or best-practice recommendation. |
| ⚪ **Info** | Informational observation. No action required. |"""


def _quantitative_overview(result: AnalysisResult) -> str:
    counts = result.summary_counts()
    total = len(result.findings)

    # Severity breakdown table
    sev_rows = []
    for sev in _SEVERITY_ORDER:
        c = counts.get(sev.value, 0)
        pct = f"{c / total * 100:.0f}%" if total else "0%"
        emoji = _SEVERITY_EMOJI[sev]
        sev_rows.append(f"| {emoji} {sev.value.capitalize()} | {c} | {pct} |")
    sev_table = "\n".join(sev_rows)

    # Category breakdown
    by_cat = result.findings_by_category()
    cat_rows = []
    for cat in sorted(by_cat.keys()):
        fs = by_cat[cat]
        crit = sum(1 for f in fs if f.severity == Severity.CRITICAL)
        hi = sum(1 for f in fs if f.severity == Severity.HIGH)
        med = sum(1 for f in fs if f.severity == Severity.MEDIUM)
        lo = sum(1 for f in fs if f.severity == Severity.LOW)
        cat_rows.append(
            f"| {cat} | {len(fs)} | {crit} | {hi} | {med} | {lo} |"
        )
    cat_table = "\n".join(cat_rows)

    return f"""## 3. Quantitative Overview

### Findings by Severity

| Severity | Count | Percentage |
|----------|-------|------------|
{sev_table}
| **Total** | **{total}** | **100%** |

### Findings by Category

| Category | Total | Critical | High | Medium | Low |
|----------|-------|----------|------|--------|-----|
{cat_table}"""


def _detailed_findings(result: AnalysisResult) -> str:
    by_cat = result.findings_by_category()

    if not by_cat:
        return "## 4. Detailed Findings\n\nNo findings were identified."

    sections = ["## 4. Detailed Findings"]

    for cat in sorted(by_cat.keys()):
        findings = sorted(
            by_cat[cat], key=lambda f: _SEVERITY_ORDER.index(f.severity)
        )
        sections.append(f"\n### 4.{_cat_num(cat)}. {cat}\n")

        for f in findings:
            emoji = _SEVERITY_EMOJI[f.severity]
            sections.append(
                f"#### {emoji} {f.id}: {f.title}\n"
                f"\n"
                f"- **Severity:** {f.severity.value.capitalize()}\n"
                f"- **Affected Object:** `{f.affected_object}`\n"
                f"\n"
                f"**Description:**\n"
                f"{f.description}\n"
                f"\n"
                f"**Recommendation:**\n"
                f"{f.recommendation}\n"
            )

            if f.details:
                detail_items = _format_details(f.details)
                if detail_items:
                    sections.append(
                        f"<details>\n<summary>Details</summary>\n\n"
                        f"{detail_items}\n"
                        f"</details>\n"
                    )

    return "\n".join(sections)


def _recommendations(result: AnalysisResult) -> str:
    """Build a prioritized action plan from findings."""
    sections = ["## 5. Recommendations & Action Plan"]

    # Group by priority tiers
    tiers: dict[str, list[Finding]] = {
        "Immediate (Critical)": [],
        "Short-Term (High)": [],
        "Medium-Term (Medium)": [],
        "Long-Term (Low)": [],
    }

    for f in result.findings:
        if f.severity == Severity.CRITICAL:
            tiers["Immediate (Critical)"].append(f)
        elif f.severity == Severity.HIGH:
            tiers["Short-Term (High)"].append(f)
        elif f.severity == Severity.MEDIUM:
            tiers["Medium-Term (Medium)"].append(f)
        elif f.severity == Severity.LOW:
            tiers["Long-Term (Low)"].append(f)

    for tier_name, findings in tiers.items():
        if not findings:
            continue

        sections.append(f"\n### {tier_name}\n")

        # Deduplicate recommendations
        seen_recs: set[str] = set()
        for i, f in enumerate(findings, 1):
            rec = f.recommendation
            if rec in seen_recs:
                continue
            seen_recs.add(rec)

            sections.append(
                f"{i}. **{f.title}** (`{f.affected_object}`)\n"
                f"   - Action: {rec}\n"
            )

    if all(len(v) == 0 for v in tiers.values()):
        sections.append(
            "\nNo action items identified. The project follows "
            "recommended practices."
        )

    return "\n".join(sections)


def _appendix_metrics(result: AnalysisResult) -> str:
    if not result.metrics:
        return "## Appendix A: Full Metrics\n\nNo metrics collected."

    rows = []
    for m in result.metrics:
        val = f"{m.value}{m.unit}" if m.unit else str(m.value)
        rows.append(
            f"| {m.name} | {val} | {m.benchmark or '—'} | {m.status or '—'} |"
        )
    table = "\n".join(rows)

    return f"""## Appendix A: Full Metrics

| Metric | Value | Benchmark | Status |
|--------|-------|-----------|--------|
{table}"""


def _appendix_all_findings(result: AnalysisResult) -> str:
    if not result.findings:
        return "## Appendix B: All Findings\n\nNone."

    rows = []
    for f in sorted(
        result.findings,
        key=lambda x: _SEVERITY_ORDER.index(x.severity),
    ):
        emoji = _SEVERITY_EMOJI[f.severity]
        rows.append(
            f"| {f.id} | {emoji} {f.severity.value.capitalize()} "
            f"| {f.category.value} | {f.title} | `{f.affected_object}` |"
        )
    table = "\n".join(rows)

    return f"""## Appendix B: All Findings

| ID | Severity | Category | Title | Affected Object |
|----|----------|----------|-------|-----------------|
{table}"""


# ── Helpers ───────────────────────────────────────────────────────────

_CAT_NUMS: dict[str, int] = {}
_CAT_COUNTER = 0


def _cat_num(cat: str) -> int:
    global _CAT_COUNTER
    if cat not in _CAT_NUMS:
        _CAT_COUNTER += 1
        _CAT_NUMS[cat] = _CAT_COUNTER
    return _CAT_NUMS[cat]


def _format_details(details: dict[str, Any]) -> str:
    lines = []
    for k, v in details.items():
        if isinstance(v, list):
            if v:
                items = "\n".join(f"  - `{item}`" for item in v[:25])
                lines.append(f"- **{k}:**\n{items}")
                if len(v) > 25:
                    lines.append(f"  - ... and {len(v) - 25} more")
        else:
            lines.append(f"- **{k}:** {v}")
    return "\n".join(lines)
