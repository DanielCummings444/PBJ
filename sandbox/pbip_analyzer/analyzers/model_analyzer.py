"""Semantic model structure analyzer.

Examines tables, columns, partitions, hierarchies, and overall model
complexity to surface data-modeling issues and best-practice violations.
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
MAX_TABLES = 50
MAX_COLUMNS_PER_TABLE = 100
MAX_TOTAL_COLUMNS = 500
MAX_CALC_COLUMNS = 20
HIDDEN_COLUMN_RATIO_WARN = 0.5
UNDOCUMENTED_TABLE_THRESHOLD = 0.5


def analyze_model(result: AnalysisResult) -> None:
    """Run model-level analysis and append findings/metrics to *result*."""
    model = result.model
    if model is None:
        return

    _id = 0

    def _next_id() -> str:
        nonlocal _id
        _id += 1
        return f"MDL-{_id:03d}"

    tables = model.tables
    all_cols = model.all_columns
    all_measures = model.all_measures
    calc_cols = model.all_calculated_columns
    hierarchies = model.all_hierarchies

    # ── Metrics ───────────────────────────────────────────────────────
    result.metrics.extend([
        QuantitativeMetric(
            "Total tables", len(tables), "count",
            benchmark=f"<= {MAX_TABLES}",
            status="warning" if len(tables) > MAX_TABLES else "good",
        ),
        QuantitativeMetric(
            "Total columns", len(all_cols), "count",
            benchmark=f"<= {MAX_TOTAL_COLUMNS}",
            status="warning" if len(all_cols) > MAX_TOTAL_COLUMNS else "good",
        ),
        QuantitativeMetric(
            "Total measures", len(all_measures), "count",
        ),
        QuantitativeMetric(
            "Calculated columns", len(calc_cols), "count",
            benchmark=f"<= {MAX_CALC_COLUMNS}",
            status="warning" if len(calc_cols) > MAX_CALC_COLUMNS else "good",
        ),
        QuantitativeMetric(
            "Hierarchies", len(hierarchies), "count",
        ),
        QuantitativeMetric(
            "Compatibility level", model.compatibility_level, "",
        ),
    ])

    # ── Table count ───────────────────────────────────────────────────
    if len(tables) > MAX_TABLES:
        result.findings.append(Finding(
            id=_next_id(),
            title="Excessive table count",
            description=(
                f"The model contains {len(tables)} tables, which exceeds "
                f"the recommended maximum of {MAX_TABLES}."
            ),
            severity=Severity.HIGH,
            category=Category.DATA_MODELING,
            affected_object="Model",
            recommendation=(
                "Consolidate tables where possible. Remove unused import "
                "tables and consider flattening star-schema arms that carry "
                "only a few attributes."
            ),
            details={"table_count": len(tables)},
        ))

    # ── Wide tables ───────────────────────────────────────────────────
    for tbl in tables:
        cols = tbl.get("columns", [])
        if len(cols) > MAX_COLUMNS_PER_TABLE:
            result.findings.append(Finding(
                id=_next_id(),
                title=f"Wide table: {tbl['name']}",
                description=(
                    f"Table '{tbl['name']}' has {len(cols)} columns "
                    f"(threshold: {MAX_COLUMNS_PER_TABLE})."
                ),
                severity=Severity.MEDIUM,
                category=Category.PERFORMANCE,
                affected_object=f"Table: {tbl['name']}",
                recommendation=(
                    "Remove unused columns at the source or split into "
                    "related dimension tables."
                ),
                details={"column_count": len(cols)},
            ))

    # ── Calculated columns ────────────────────────────────────────────
    if len(calc_cols) > MAX_CALC_COLUMNS:
        result.findings.append(Finding(
            id=_next_id(),
            title="High number of calculated columns",
            description=(
                f"{len(calc_cols)} calculated columns detected. Each one "
                "materializes into the in-memory model and consumes RAM."
            ),
            severity=Severity.MEDIUM,
            category=Category.PERFORMANCE,
            affected_object="Model (calculated columns)",
            recommendation=(
                "Replace calculated columns with measures where the "
                "calculation is only needed at query time, or push the "
                "logic into the source query / Power Query."
            ),
            details={
                "calc_columns": [
                    f"{c['_table']}.{c['name']}" for c in calc_cols
                ]
            },
        ))

    # ── Hidden column ratio ───────────────────────────────────────────
    if all_cols:
        hidden = [c for c in all_cols if c.get("isHidden")]
        ratio = len(hidden) / len(all_cols)
        result.metrics.append(QuantitativeMetric(
            "Hidden column ratio", f"{ratio:.0%}", "",
            benchmark=f"< {HIDDEN_COLUMN_RATIO_WARN:.0%}",
            status="warning" if ratio >= HIDDEN_COLUMN_RATIO_WARN else "good",
        ))
        if ratio >= HIDDEN_COLUMN_RATIO_WARN:
            result.findings.append(Finding(
                id=_next_id(),
                title="High proportion of hidden columns",
                description=(
                    f"{len(hidden)} of {len(all_cols)} columns "
                    f"({ratio:.0%}) are hidden. While hiding columns is "
                    "fine, a very high ratio may indicate unused columns "
                    "still stored in the model."
                ),
                severity=Severity.LOW,
                category=Category.MAINTENANCE,
                affected_object="Model",
                recommendation=(
                    "Review hidden columns and remove any that are not "
                    "referenced by measures, relationships, or row-level "
                    "security expressions."
                ),
            ))

    # ── Undocumented tables ───────────────────────────────────────────
    undoc_tables = [
        t["name"] for t in tables if not t.get("description")
    ]
    if tables:
        undoc_ratio = len(undoc_tables) / len(tables)
        result.metrics.append(QuantitativeMetric(
            "Table documentation coverage",
            f"{1 - undoc_ratio:.0%}", "",
            status="warning" if undoc_ratio > UNDOCUMENTED_TABLE_THRESHOLD else "good",
        ))
        if undoc_ratio > UNDOCUMENTED_TABLE_THRESHOLD:
            result.findings.append(Finding(
                id=_next_id(),
                title="Low table documentation coverage",
                description=(
                    f"{len(undoc_tables)} of {len(tables)} tables lack a "
                    "description."
                ),
                severity=Severity.LOW,
                category=Category.DOCUMENTATION,
                affected_object="Model",
                recommendation=(
                    "Add descriptions to all tables to improve "
                    "discoverability and support AI-assisted Q&A features."
                ),
                details={"undocumented_tables": undoc_tables},
            ))

    # ── Undocumented measures ─────────────────────────────────────────
    undoc_measures = [
        f"{m['_table']}.{m['name']}"
        for m in all_measures if not m.get("description")
    ]
    if all_measures:
        undoc_m_ratio = len(undoc_measures) / len(all_measures)
        result.metrics.append(QuantitativeMetric(
            "Measure documentation coverage",
            f"{1 - undoc_m_ratio:.0%}", "",
            status="warning" if undoc_m_ratio > UNDOCUMENTED_TABLE_THRESHOLD else "good",
        ))
        if undoc_m_ratio > UNDOCUMENTED_TABLE_THRESHOLD:
            result.findings.append(Finding(
                id=_next_id(),
                title="Low measure documentation coverage",
                description=(
                    f"{len(undoc_measures)} of {len(all_measures)} measures "
                    "lack a description."
                ),
                severity=Severity.LOW,
                category=Category.DOCUMENTATION,
                affected_object="Model",
                recommendation=(
                    "Add descriptions to measures, especially KPIs and "
                    "complex calculations, to aid report authors and "
                    "end-users."
                ),
            ))

    # ── Tables without relationships ──────────────────────────────────
    rel_tables = set()
    for r in model.relationships:
        rel_tables.add(r.get("fromTable", ""))
        rel_tables.add(r.get("toTable", ""))

    orphan_tables = [
        t["name"] for t in tables
        if t["name"] not in rel_tables
        and not t.get("isHidden")
        and t.get("columns")  # non-empty
    ]
    if orphan_tables:
        result.findings.append(Finding(
            id=_next_id(),
            title="Orphan tables (no relationships)",
            description=(
                f"{len(orphan_tables)} visible table(s) have no "
                "relationships: " + ", ".join(orphan_tables)
            ),
            severity=Severity.MEDIUM,
            category=Category.DATA_MODELING,
            affected_object="Model",
            recommendation=(
                "Either connect these tables via relationships or hide "
                "them if they are helper/staging tables."
            ),
            details={"orphan_tables": orphan_tables},
        ))

    # ── Columns without summarizeBy: none ─────────────────────────────
    non_numeric_summarize = []
    for c in all_cols:
        if (
            c.get("dataType") in ("string", "boolean", "binary")
            and c.get("summarizeBy", "default") not in ("none", "")
        ):
            non_numeric_summarize.append(
                f"{c['_table']}.{c['name']} ({c.get('summarizeBy')})"
            )

    if non_numeric_summarize:
        result.findings.append(Finding(
            id=_next_id(),
            title="Non-numeric columns with default aggregation",
            description=(
                f"{len(non_numeric_summarize)} text/boolean columns still "
                "have a default summarization that may confuse report authors."
            ),
            severity=Severity.LOW,
            category=Category.BEST_PRACTICES,
            affected_object="Model",
            recommendation=(
                "Set summarizeBy to 'none' for non-numeric columns to "
                "prevent accidental implicit aggregation."
            ),
            details={"columns": non_numeric_summarize[:20]},
        ))
