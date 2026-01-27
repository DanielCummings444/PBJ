"""Relationship structure analyzer.

Examines relationships for bi-directional filtering, many-to-many joins,
inactive relationships, missing keys, and potential circular paths.
"""

from __future__ import annotations

from pbip_analyzer.models.findings import (
    AnalysisResult,
    Category,
    Finding,
    QuantitativeMetric,
    Severity,
)


def analyze_relationships(result: AnalysisResult) -> None:
    """Run relationship analysis and append findings/metrics."""
    model = result.model
    if model is None:
        return

    _id = 0

    def _next_id() -> str:
        nonlocal _id
        _id += 1
        return f"REL-{_id:03d}"

    rels = model.relationships

    # ── Metrics ───────────────────────────────────────────────────────
    total = len(rels)
    active_rels = [r for r in rels if r.get("isActive", True)]
    inactive_rels = [r for r in rels if not r.get("isActive", True)]
    bidir = [
        r for r in rels
        if r.get("crossFilteringBehavior", "").lower() == "bothdirections"
    ]
    m2m = [
        r for r in rels
        if r.get("fromCardinality") == "many"
        and r.get("toCardinality") == "many"
    ]

    result.metrics.extend([
        QuantitativeMetric(
            "Total relationships", total, "count",
        ),
        QuantitativeMetric(
            "Active relationships", len(active_rels), "count",
        ),
        QuantitativeMetric(
            "Inactive relationships", len(inactive_rels), "count",
            benchmark="Minimize",
            status="warning" if inactive_rels else "good",
        ),
        QuantitativeMetric(
            "Bi-directional relationships", len(bidir), "count",
            benchmark="Minimize",
            status="warning" if bidir else "good",
        ),
        QuantitativeMetric(
            "Many-to-many relationships", len(m2m), "count",
            benchmark="0",
            status="critical" if m2m else "good",
        ),
    ])

    # ── Bi-directional filtering ──────────────────────────────────────
    for r in bidir:
        label = _rel_label(r)
        result.findings.append(Finding(
            id=_next_id(),
            title=f"Bi-directional cross-filter: {label}",
            description=(
                f"Relationship {label} uses bi-directional cross-filtering. "
                "This can cause ambiguous filter paths, unexpected results, "
                "and degraded query performance."
            ),
            severity=Severity.HIGH,
            category=Category.RELATIONSHIPS,
            affected_object=label,
            recommendation=(
                "Switch to one-direction filtering unless the bi-directional "
                "filter is explicitly required (e.g., bridge tables in "
                "many-to-many patterns). If needed, apply bi-directional "
                "filtering only in the specific measure via CROSSFILTER()."
            ),
        ))

    # ── Many-to-many ──────────────────────────────────────────────────
    for r in m2m:
        label = _rel_label(r)
        result.findings.append(Finding(
            id=_next_id(),
            title=f"Many-to-many relationship: {label}",
            description=(
                f"Relationship {label} is many-to-many. This cardinality "
                "can produce duplicated or missing values in aggregations."
            ),
            severity=Severity.CRITICAL,
            category=Category.RELATIONSHIPS,
            affected_object=label,
            recommendation=(
                "Introduce a bridge table or refactor the data model to "
                "one-to-many. If many-to-many is intentional, document "
                "the expected behavior and validate aggregation results."
            ),
        ))

    # ── Inactive relationships ────────────────────────────────────────
    if len(inactive_rels) > 3:
        names = [_rel_label(r) for r in inactive_rels]
        result.findings.append(Finding(
            id=_next_id(),
            title="Many inactive relationships",
            description=(
                f"{len(inactive_rels)} inactive relationships detected. "
                "While role-playing dimensions legitimately use inactive "
                "relationships, too many can indicate model design issues."
            ),
            severity=Severity.MEDIUM,
            category=Category.RELATIONSHIPS,
            affected_object="Model",
            recommendation=(
                "Review inactive relationships. Remove any that are unused "
                "and ensure role-playing dimension patterns are documented."
            ),
            details={"inactive_relationships": names},
        ))

    # ── Duplicate relationship paths ──────────────────────────────────
    path_set: dict[tuple[str, str], list[dict]] = {}
    for r in rels:
        key = tuple(sorted([r.get("fromTable", ""), r.get("toTable", "")]))
        path_set.setdefault(key, []).append(r)

    for key, group in path_set.items():
        if len(group) > 1:
            labels = [_rel_label(r) for r in group]
            result.findings.append(Finding(
                id=_next_id(),
                title=f"Multiple relationships between {key[0]} and {key[1]}",
                description=(
                    f"Found {len(group)} relationships between tables "
                    f"{key[0]} and {key[1]}: {', '.join(labels)}. "
                    "Only one can be active at a time."
                ),
                severity=Severity.MEDIUM,
                category=Category.RELATIONSHIPS,
                affected_object=f"{key[0]} <-> {key[1]}",
                recommendation=(
                    "Verify this is a role-playing dimension pattern. If "
                    "not, consolidate into a single relationship."
                ),
                details={"relationships": labels},
            ))

    # ── Circular path detection (simple cycle check) ──────────────────
    _detect_cycles(active_rels, result, _next_id)

    # ── Tables with many incoming relationships ───────────────────────
    incoming: dict[str, int] = {}
    for r in active_rels:
        to_tbl = r.get("toTable", "")
        incoming[to_tbl] = incoming.get(to_tbl, 0) + 1

    for tbl, count in incoming.items():
        if count > 8:
            result.findings.append(Finding(
                id=_next_id(),
                title=f"Hub table with many relationships: {tbl}",
                description=(
                    f"Table '{tbl}' has {count} incoming relationships, "
                    "making it a heavily-connected hub."
                ),
                severity=Severity.LOW,
                category=Category.PERFORMANCE,
                affected_object=f"Table: {tbl}",
                recommendation=(
                    "This is common for date or shared dimensions. Verify "
                    "that filter propagation paths are optimal."
                ),
            ))


def _rel_label(r: dict) -> str:
    return (
        f"{r.get('fromTable', '?')}.{r.get('fromColumn', '?')} -> "
        f"{r.get('toTable', '?')}.{r.get('toColumn', '?')}"
    )


def _detect_cycles(
    rels: list[dict],
    result: AnalysisResult,
    next_id,
) -> None:
    """Simple DFS-based cycle detection on the active relationship graph."""
    graph: dict[str, list[str]] = {}
    for r in rels:
        src = r.get("fromTable", "")
        dst = r.get("toTable", "")
        graph.setdefault(src, []).append(dst)
        # Bi-directional edges propagate both ways
        if r.get("crossFilteringBehavior", "").lower() == "bothdirections":
            graph.setdefault(dst, []).append(src)

    visited: set[str] = set()
    in_stack: set[str] = set()
    cycle_found = False

    def dfs(node: str) -> bool:
        nonlocal cycle_found
        visited.add(node)
        in_stack.add(node)
        for neighbor in graph.get(node, []):
            if neighbor in in_stack:
                cycle_found = True
                return True
            if neighbor not in visited:
                if dfs(neighbor):
                    return True
        in_stack.discard(node)
        return False

    for node in graph:
        if node not in visited:
            dfs(node)

    if cycle_found:
        result.findings.append(Finding(
            id=next_id(),
            title="Circular relationship path detected",
            description=(
                "A circular filter path exists in the active relationship "
                "graph. This can cause ambiguous query results."
            ),
            severity=Severity.CRITICAL,
            category=Category.RELATIONSHIPS,
            affected_object="Model",
            recommendation=(
                "Break the cycle by making one relationship inactive or "
                "switching a bi-directional relationship to one-direction."
            ),
        ))
