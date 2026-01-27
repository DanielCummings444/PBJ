"""DAX expression quality analyzer.

Examines measure and calculated-column expressions for complexity,
anti-patterns, and best-practice violations.
"""

from __future__ import annotations

import re

from pbip_analyzer.models.findings import (
    AnalysisResult,
    Category,
    Finding,
    QuantitativeMetric,
    Severity,
)

# ── Thresholds ────────────────────────────────────────────────────────
MAX_EXPRESSION_LENGTH = 1000
MAX_NESTING_DEPTH = 5
ITERATOR_FUNCTIONS = {
    "SUMX", "AVERAGEX", "MINX", "MAXX", "COUNTX",
    "RANKX", "PRODUCTX", "CONCATENATEX", "ADDCOLUMNS",
    "SELECTCOLUMNS", "GENERATE", "GENERATEALL",
}
CONTEXT_TRANSITION_FUNCTIONS = {"CALCULATE", "CALCULATETABLE"}
DEPRECATED_FUNCTIONS = {
    "USERELATIONSHIP": "Use CALCULATE with USERELATIONSHIP sparingly",
    "EARLIER": "Replace with VAR / CALCULATE patterns",
    "EARLIEST": "Replace with VAR / CALCULATE patterns",
    "LOOKUPVALUE": "Consider using relationships + RELATED instead",
}
TIME_INTEL_FUNCTIONS = {
    "TOTALYTD", "TOTALQTD", "TOTALMTD",
    "DATESYTD", "DATESQTD", "DATESMTD",
    "SAMEPERIODLASTYEAR", "PREVIOUSMONTH", "PREVIOUSQUARTER",
    "PREVIOUSYEAR", "DATEADD", "DATESINPERIOD",
    "PARALLELPERIOD", "OPENINGBALANCEMONTH",
}


def analyze_dax(result: AnalysisResult) -> None:
    """Run DAX analysis and append findings/metrics to *result*."""
    model = result.model
    if model is None:
        return

    _id = 0

    def _next_id() -> str:
        nonlocal _id
        _id += 1
        return f"DAX-{_id:03d}"

    all_measures = model.all_measures
    calc_cols = model.all_calculated_columns

    all_expressions = []
    for m in all_measures:
        all_expressions.append({
            "name": f"{m['_table']}[{m['name']}]",
            "expression": m.get("expression", ""),
            "kind": "measure",
        })
    for c in calc_cols:
        all_expressions.append({
            "name": f"{c['_table']}[{c['name']}]",
            "expression": c.get("expression", ""),
            "kind": "calculated_column",
        })

    # ── Aggregate metrics ─────────────────────────────────────────────
    total_expr = len(all_expressions)
    long_exprs = []
    deeply_nested = []
    iterator_usages = []
    context_transition_count = 0
    deprecated_usages: list[tuple[str, str, str]] = []
    time_intel_count = 0
    no_var_complex = []

    for item in all_expressions:
        expr = item["expression"]
        name = item["name"]

        if not expr:
            continue

        # Length check
        if len(expr) > MAX_EXPRESSION_LENGTH:
            long_exprs.append((name, len(expr)))

        # Nesting depth (count max nested parentheses)
        depth = _max_paren_depth(expr)
        if depth > MAX_NESTING_DEPTH:
            deeply_nested.append((name, depth))

        # Iterator functions
        upper_expr = expr.upper()
        for fn in ITERATOR_FUNCTIONS:
            if fn in upper_expr:
                iterator_usages.append((name, fn))

        # Context transitions
        for fn in CONTEXT_TRANSITION_FUNCTIONS:
            if fn in upper_expr:
                context_transition_count += 1

        # Deprecated patterns
        for fn, advice in DEPRECATED_FUNCTIONS.items():
            if fn in upper_expr:
                deprecated_usages.append((name, fn, advice))

        # Time intelligence
        for fn in TIME_INTEL_FUNCTIONS:
            if fn in upper_expr:
                time_intel_count += 1

        # Complex expression without VAR usage
        if len(expr) > 300 and "VAR " not in upper_expr:
            no_var_complex.append(name)

    # ── Metrics ───────────────────────────────────────────────────────
    result.metrics.extend([
        QuantitativeMetric(
            "DAX expressions", total_expr, "count",
        ),
        QuantitativeMetric(
            "Long expressions (>{} chars)".format(MAX_EXPRESSION_LENGTH),
            len(long_exprs), "count",
            benchmark="0",
            status="warning" if long_exprs else "good",
        ),
        QuantitativeMetric(
            "Deeply nested expressions (>{} levels)".format(MAX_NESTING_DEPTH),
            len(deeply_nested), "count",
            benchmark="0",
            status="warning" if deeply_nested else "good",
        ),
        QuantitativeMetric(
            "Iterator function usages", len(iterator_usages), "count",
        ),
        QuantitativeMetric(
            "CALCULATE/CALCULATETABLE calls", context_transition_count, "count",
        ),
        QuantitativeMetric(
            "Time intelligence function usages", time_intel_count, "count",
        ),
    ])

    # ── Findings ──────────────────────────────────────────────────────
    for name, length in long_exprs:
        result.findings.append(Finding(
            id=_next_id(),
            title=f"Overly long DAX expression: {name}",
            description=(
                f"{name} has {length} characters. Long expressions are "
                "harder to maintain and often indicate a need for "
                "decomposition."
            ),
            severity=Severity.MEDIUM,
            category=Category.DAX_QUALITY,
            affected_object=name,
            recommendation=(
                "Break the expression into intermediate measures or use "
                "VAR statements to improve readability and debuggability."
            ),
            details={"length": length},
        ))

    for name, depth in deeply_nested:
        result.findings.append(Finding(
            id=_next_id(),
            title=f"Deeply nested expression: {name}",
            description=(
                f"{name} has a nesting depth of {depth} "
                f"(threshold: {MAX_NESTING_DEPTH})."
            ),
            severity=Severity.MEDIUM,
            category=Category.DAX_QUALITY,
            affected_object=name,
            recommendation=(
                "Flatten nested logic using VAR/RETURN blocks or extract "
                "sub-measures."
            ),
            details={"depth": depth},
        ))

    # Nested iterators (iterator inside another iterator)
    _check_nested_iterators(all_expressions, result, _next_id)

    for name, fn, advice in deprecated_usages:
        result.findings.append(Finding(
            id=_next_id(),
            title=f"Deprecated/discouraged function: {fn} in {name}",
            description=f"{name} uses {fn}. {advice}.",
            severity=Severity.MEDIUM,
            category=Category.DAX_QUALITY,
            affected_object=name,
            recommendation=advice,
            details={"function": fn},
        ))

    for name in no_var_complex:
        result.findings.append(Finding(
            id=_next_id(),
            title=f"Complex expression without VARs: {name}",
            description=(
                f"{name} is longer than 300 characters but does not use "
                "VAR statements."
            ),
            severity=Severity.LOW,
            category=Category.DAX_QUALITY,
            affected_object=name,
            recommendation=(
                "Use VAR/RETURN to name intermediate results, which "
                "improves readability and can improve performance by "
                "preventing repeated evaluation."
            ),
        ))

    # ── Measures with no format string ────────────────────────────────
    unformatted = [
        f"{m['_table']}[{m['name']}]"
        for m in all_measures
        if not m.get("formatString")
    ]
    if unformatted:
        result.metrics.append(QuantitativeMetric(
            "Measures without format string",
            len(unformatted), "count",
            benchmark="0",
            status="warning" if unformatted else "good",
        ))
        if len(unformatted) > 3:
            result.findings.append(Finding(
                id=_next_id(),
                title="Measures without format strings",
                description=(
                    f"{len(unformatted)} measures lack a format string, "
                    "which may display raw numbers without currency, "
                    "percentage, or decimal formatting."
                ),
                severity=Severity.LOW,
                category=Category.BEST_PRACTICES,
                affected_object="Model",
                recommendation=(
                    "Add formatString to all measures for consistent "
                    "display across reports."
                ),
                details={"measures": unformatted[:15]},
            ))


def _max_paren_depth(expr: str) -> int:
    """Return the maximum parenthesis nesting depth."""
    depth = 0
    max_depth = 0
    in_string = False
    quote_char = ""
    for ch in expr:
        if in_string:
            if ch == quote_char:
                in_string = False
            continue
        if ch in ('"', "'"):
            in_string = True
            quote_char = ch
            continue
        if ch == "(":
            depth += 1
            max_depth = max(max_depth, depth)
        elif ch == ")":
            depth -= 1
    return max_depth


def _check_nested_iterators(
    all_expressions: list[dict],
    result: AnalysisResult,
    next_id,
) -> None:
    """Detect iterator functions nested inside other iterators."""
    pattern = re.compile(
        r"\b(" + "|".join(ITERATOR_FUNCTIONS) + r")\s*\(",
        re.IGNORECASE,
    )

    for item in all_expressions:
        expr = item["expression"]
        if not expr:
            continue

        matches = list(pattern.finditer(expr))
        if len(matches) >= 2:
            fns_found = [m.group(1).upper() for m in matches]
            result.findings.append(Finding(
                id=next_id(),
                title=f"Nested iterators in {item['name']}",
                description=(
                    f"{item['name']} contains multiple iterator functions "
                    f"({', '.join(fns_found)}). Nested iterators can cause "
                    "O(n^2) or worse scan behavior."
                ),
                severity=Severity.HIGH,
                category=Category.PERFORMANCE,
                affected_object=item["name"],
                recommendation=(
                    "Refactor to reduce iterator nesting. Use SUMMARIZE + "
                    "ADDCOLUMNS with a single outer iterator, or push "
                    "aggregation into sub-measures."
                ),
                details={"functions": fns_found},
            ))
