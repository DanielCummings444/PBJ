"""Performance-focused analyzer.

Aggregates signals from the model, DAX, relationships, and report
structure to produce overall performance risk findings.
"""

from __future__ import annotations

from pbip_analyzer.models.findings import (
    AnalysisResult,
    Category,
    Finding,
    QuantitativeMetric,
    Severity,
)


def analyze_performance(result: AnalysisResult) -> None:
    """Run cross-cutting performance analysis."""
    model = result.model
    report = result.report

    _id = 0

    def _next_id() -> str:
        nonlocal _id
        _id += 1
        return f"PERF-{_id:03d}"

    if model is None:
        return

    # ── Import mode partition check ───────────────────────────────────
    import_tables = []
    directquery_tables = []
    dual_tables = []

    for tbl in model.tables:
        modes = set()
        for part in tbl.get("partitions", []):
            mode = part.get("mode", "").lower()
            if mode:
                modes.add(mode)
        name = tbl["name"]
        if "import" in modes and "directquery" in modes:
            dual_tables.append(name)
        elif "directquery" in modes:
            directquery_tables.append(name)
        else:
            import_tables.append(name)

    result.metrics.extend([
        QuantitativeMetric(
            "Import-mode tables", len(import_tables), "count",
        ),
        QuantitativeMetric(
            "DirectQuery tables", len(directquery_tables), "count",
            benchmark="0 (prefer import)",
            status="warning" if directquery_tables else "good",
        ),
        QuantitativeMetric(
            "Dual-mode tables", len(dual_tables), "count",
        ),
    ])

    if directquery_tables:
        result.findings.append(Finding(
            id=_next_id(),
            title="DirectQuery tables detected",
            description=(
                f"{len(directquery_tables)} table(s) use DirectQuery mode: "
                f"{', '.join(directquery_tables[:10])}. DirectQuery sends "
                "every user interaction as a live query to the data source."
            ),
            severity=Severity.MEDIUM,
            category=Category.PERFORMANCE,
            affected_object="Model",
            recommendation=(
                "Where possible, switch to import mode for better "
                "performance. Use DirectQuery only when data freshness or "
                "data volume requires it. Consider aggregation tables as "
                "a hybrid approach."
            ),
            details={"tables": directquery_tables},
        ))

    # ── Composite model risk ──────────────────────────────────────────
    if import_tables and directquery_tables:
        result.findings.append(Finding(
            id=_next_id(),
            title="Composite model detected",
            description=(
                "The model mixes import and DirectQuery storage modes. "
                "Cross-source joins can be slow because they require "
                "client-side processing."
            ),
            severity=Severity.MEDIUM,
            category=Category.PERFORMANCE,
            affected_object="Model",
            recommendation=(
                "Minimize cross-source relationships. Use aggregation "
                "tables to serve common queries from import-mode data."
            ),
        ))

    # ── Overall risk score ────────────────────────────────────────────
    risk_score = _compute_risk_score(result)
    result.metrics.append(QuantitativeMetric(
        "Performance risk score", risk_score, "/100",
        benchmark="<= 40",
        status=(
            "good" if risk_score <= 40
            else "warning" if risk_score <= 70
            else "critical"
        ),
    ))


def _compute_risk_score(result: AnalysisResult) -> int:
    """Compute a 0-100 performance risk score from existing findings."""
    score = 0

    severity_weights = {
        "critical": 20,
        "high": 10,
        "medium": 5,
        "low": 2,
        "info": 0,
    }

    perf_findings = [
        f for f in result.findings
        if f.category in (Category.PERFORMANCE, Category.RELATIONSHIPS)
    ]

    for f in perf_findings:
        score += severity_weights.get(f.severity.value, 0)

    return min(score, 100)
