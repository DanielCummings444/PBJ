"""Report structure analyzer.

Examines page count, visual density, visual types, and layout patterns
to surface UX and performance concerns.
"""

from __future__ import annotations

from pbip_analyzer.models.findings import (
    AnalysisResult,
    Category,
    Finding,
    QuantitativeMetric,
    Severity,
)

# ── Thresholds ────────────────────────────────────────────────────────
MAX_PAGES = 20
MAX_VISUALS_PER_PAGE = 15
MAX_TOTAL_VISUALS = 150


def analyze_report(result: AnalysisResult) -> None:
    """Run report structure analysis and append findings/metrics."""
    report = result.report
    if report is None:
        return

    _id = 0

    def _next_id() -> str:
        nonlocal _id
        _id += 1
        return f"RPT-{_id:03d}"

    pages = report.pages
    all_visuals = report.visuals

    # ── Metrics ───────────────────────────────────────────────────────
    result.metrics.extend([
        QuantitativeMetric(
            "Report pages", len(pages), "count",
            benchmark=f"<= {MAX_PAGES}",
            status="warning" if len(pages) > MAX_PAGES else "good",
        ),
        QuantitativeMetric(
            "Total visuals", len(all_visuals), "count",
            benchmark=f"<= {MAX_TOTAL_VISUALS}",
            status=(
                "critical" if len(all_visuals) > MAX_TOTAL_VISUALS
                else "good"
            ),
        ),
        QuantitativeMetric(
            "Bookmarks", len(report.bookmarks), "count",
        ),
        QuantitativeMetric(
            "Report format", report.format_version or "unknown", "",
        ),
    ])

    # ── Visual type distribution ──────────────────────────────────────
    type_counts: dict[str, int] = {}
    for v in all_visuals:
        vtype = (
            v.get("visual", {}).get("visualType", "")
            or v.get("visualType", "unknown")
        )
        type_counts[vtype] = type_counts.get(vtype, 0) + 1

    if type_counts:
        result.metrics.append(QuantitativeMetric(
            "Visual types used", len(type_counts), "count",
        ))

    # ── Page count ────────────────────────────────────────────────────
    if len(pages) > MAX_PAGES:
        result.findings.append(Finding(
            id=_next_id(),
            title="Excessive page count",
            description=(
                f"The report has {len(pages)} pages "
                f"(threshold: {MAX_PAGES}). Large reports load slowly and "
                "are hard to navigate."
            ),
            severity=Severity.MEDIUM,
            category=Category.REPORT_DESIGN,
            affected_object="Report",
            recommendation=(
                "Split into multiple focused reports or use bookmarks and "
                "drill-through pages to reduce the page count."
            ),
        ))

    # ── Visual density per page ───────────────────────────────────────
    for page in pages:
        if not isinstance(page, dict):
            continue
        page_name = page.get("displayName", page.get("name", "?"))
        page_visuals = page.get("_visuals", [])
        vis_count = len(page_visuals)

        if vis_count > MAX_VISUALS_PER_PAGE:
            result.findings.append(Finding(
                id=_next_id(),
                title=f"Visual overload on page: {page_name}",
                description=(
                    f"Page '{page_name}' has {vis_count} visuals "
                    f"(threshold: {MAX_VISUALS_PER_PAGE}). Dense pages "
                    "increase render time and degrade user experience."
                ),
                severity=Severity.HIGH,
                category=Category.REPORT_DESIGN,
                affected_object=f"Page: {page_name}",
                recommendation=(
                    "Reduce visual count by combining related metrics into "
                    "card groups, using matrix visuals, or splitting content "
                    "across pages with drill-through links."
                ),
                details={"visual_count": vis_count},
            ))

    # ── Total visuals ─────────────────────────────────────────────────
    if len(all_visuals) > MAX_TOTAL_VISUALS:
        result.findings.append(Finding(
            id=_next_id(),
            title="Excessive total visual count",
            description=(
                f"The report contains {len(all_visuals)} visuals "
                f"(threshold: {MAX_TOTAL_VISUALS}). Each visual generates "
                "at least one DAX query on load."
            ),
            severity=Severity.HIGH,
            category=Category.PERFORMANCE,
            affected_object="Report",
            recommendation=(
                "Reduce the overall visual count. Consider consolidation, "
                "navigation pages, or splitting into separate reports."
            ),
        ))

    # ── Overlapping visuals (basic check) ─────────────────────────────
    for page in pages:
        if not isinstance(page, dict):
            continue
        page_name = page.get("displayName", page.get("name", "?"))
        pvs = page.get("_visuals", [])
        overlaps = _detect_overlaps(pvs)
        if overlaps > 2:
            result.findings.append(Finding(
                id=_next_id(),
                title=f"Overlapping visuals on page: {page_name}",
                description=(
                    f"Page '{page_name}' has {overlaps} overlapping visual "
                    "pairs, which may indicate layout issues."
                ),
                severity=Severity.LOW,
                category=Category.REPORT_DESIGN,
                affected_object=f"Page: {page_name}",
                recommendation=(
                    "Review the page layout and adjust visual positions to "
                    "eliminate unintended overlaps."
                ),
                details={"overlap_count": overlaps},
            ))


def _detect_overlaps(visuals: list[dict]) -> int:
    """Count overlapping visual pairs based on position data."""
    rects = []
    for v in visuals:
        pos = v.get("position", {})
        x = pos.get("x", 0)
        y = pos.get("y", 0)
        w = pos.get("width", 0)
        h = pos.get("height", 0)
        if w and h:
            rects.append((x, y, x + w, y + h))

    count = 0
    for i in range(len(rects)):
        for j in range(i + 1, len(rects)):
            ax1, ay1, ax2, ay2 = rects[i]
            bx1, by1, bx2, by2 = rects[j]
            if ax1 < bx2 and ax2 > bx1 and ay1 < by2 and ay2 > by1:
                count += 1
    return count
