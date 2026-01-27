"""Parser for TMDL (Tabular Model Definition Language) files.

TMDL uses an indentation-based syntax with properties defined via `:` and
expressions via `=`.  This parser handles the definition/ folder structure
containing database.tmdl, model.tmdl, relationships.tmdl, expressions.tmdl,
and per-table files under tables/.
"""

from __future__ import annotations

import re
from pathlib import Path

from pbip_analyzer.models.findings import SemanticModel


def _strip_quotes(s: str) -> str:
    s = s.strip()
    if len(s) >= 2 and s[0] == "'" and s[-1] == "'":
        return s[1:-1]
    return s


def _parse_tmdl_table(text: str) -> dict:
    """Parse a single .tmdl file for a table."""
    table: dict = {
        "name": "",
        "description": "",
        "isHidden": False,
        "columns": [],
        "measures": [],
        "partitions": [],
        "hierarchies": [],
        "annotations": [],
    }

    lines = text.splitlines()
    current_object: dict | None = None
    current_type: str = ""
    expression_lines: list[str] = []
    collecting_expression = False

    for i, raw_line in enumerate(lines):
        line = raw_line.rstrip()
        stripped = line.strip()

        # Skip blank lines and comments
        if not stripped:
            if collecting_expression:
                expression_lines.append("")
            continue

        # Description comments (/// before object declaration)
        if stripped.startswith("///"):
            desc = stripped[3:].strip()
            # Peek ahead to see which object this belongs to
            if current_object is None:
                table["description"] = desc
            continue

        indent = len(line) - len(line.lstrip())

        # Top-level table declaration
        if stripped.startswith("table ") and indent == 0:
            table["name"] = _strip_quotes(stripped[6:].strip())
            continue

        # Finish collecting multi-line expression
        if collecting_expression and indent <= 1:
            if current_object is not None and expression_lines:
                expr = "\n".join(expression_lines).strip()
                if current_type == "measure":
                    current_object["expression"] = expr
                elif current_type == "partition":
                    current_object["source_expression"] = expr
                elif current_type == "column" and current_object.get("type") == "calculated":
                    current_object["expression"] = expr
            expression_lines = []
            collecting_expression = False

        if collecting_expression:
            expression_lines.append(stripped)
            continue

        # Object declarations at indent level 1
        if indent <= 4 and indent > 0:
            # Save previous object
            if current_object is not None:
                _save_object(table, current_type, current_object)

            if stripped.startswith("column "):
                current_type = "column"
                name_part = stripped[7:].strip()
                current_object = {
                    "name": _strip_quotes(name_part),
                    "type": "data",
                    "dataType": "",
                    "isHidden": False,
                    "isKey": False,
                    "sourceColumn": "",
                    "expression": "",
                    "summarizeBy": "default",
                    "sortByColumn": "",
                    "displayFolder": "",
                    "formatString": "",
                    "annotations": [],
                }
                continue

            if stripped.startswith("measure "):
                current_type = "measure"
                # measure 'Name' = expression  OR  measure 'Name'
                m = re.match(r"measure\s+(.+?)\s*=\s*(.*)", stripped)
                if m:
                    name_part = m.group(1)
                    expr_start = m.group(2).strip()
                    current_object = {
                        "name": _strip_quotes(name_part),
                        "expression": expr_start,
                        "description": "",
                        "formatString": "",
                        "isHidden": False,
                        "displayFolder": "",
                        "annotations": [],
                    }
                    if not expr_start:
                        collecting_expression = True
                        expression_lines = []
                else:
                    name_part = stripped[8:].strip()
                    current_object = {
                        "name": _strip_quotes(name_part),
                        "expression": "",
                        "description": "",
                        "formatString": "",
                        "isHidden": False,
                        "displayFolder": "",
                        "annotations": [],
                    }
                continue

            if stripped.startswith("partition "):
                current_type = "partition"
                m = re.match(r"partition\s+(.+?)\s*=\s*(\w+)", stripped)
                mode = ""
                name_part = stripped[10:].strip()
                if m:
                    name_part = m.group(1)
                    mode = m.group(2)
                current_object = {
                    "name": _strip_quotes(name_part),
                    "mode": mode,
                    "source_expression": "",
                }
                continue

            if stripped.startswith("hierarchy "):
                current_type = "hierarchy"
                name_part = stripped[10:].strip()
                current_object = {
                    "name": _strip_quotes(name_part),
                    "levels": [],
                }
                continue

        # Properties of the current object
        if current_object is not None:
            # Boolean shorthand (e.g., `isHidden`, `isKey`)
            if stripped in ("isHidden", "isKey", "isNullable", "isUnique"):
                current_object[stripped] = True
                continue

            # Key-value property
            kv = re.match(r"(\w+)\s*:\s*(.*)", stripped)
            if kv:
                key = kv.group(1)
                val = kv.group(2).strip()
                if key in current_object:
                    current_object[key] = _strip_quotes(val)
                elif current_type == "hierarchy" and key == "column":
                    # hierarchy level column reference
                    if current_object["levels"]:
                        current_object["levels"][-1]["column"] = _strip_quotes(val)
                continue

            # Hierarchy level declaration
            if current_type == "hierarchy" and stripped.startswith("level "):
                level_name = _strip_quotes(stripped[6:].strip())
                current_object["levels"].append({"name": level_name, "column": ""})
                continue

            # Expression assignment on same line
            eq = re.match(r"(\w+)\s*=\s*(.*)", stripped)
            if eq:
                key = eq.group(1)
                val = eq.group(2).strip()
                if key == "source" and not val:
                    collecting_expression = True
                    expression_lines = []
                elif key in current_object:
                    current_object[key] = val
                continue

    # Save last object
    if current_object is not None:
        if collecting_expression and expression_lines:
            expr = "\n".join(expression_lines).strip()
            if current_type == "measure":
                current_object["expression"] = expr
        _save_object(table, current_type, current_object)

    return table


def _save_object(table: dict, obj_type: str, obj: dict) -> None:
    if obj_type == "column":
        table["columns"].append(obj)
    elif obj_type == "measure":
        table["measures"].append(obj)
    elif obj_type == "partition":
        table["partitions"].append(obj)
    elif obj_type == "hierarchy":
        table["hierarchies"].append(obj)


def _parse_relationships_tmdl(text: str) -> list[dict]:
    """Parse a relationships.tmdl file."""
    relationships: list[dict] = []
    current: dict | None = None

    for raw_line in text.splitlines():
        stripped = raw_line.strip()
        if not stripped or stripped.startswith("///"):
            continue

        if stripped.startswith("relationship "):
            if current is not None:
                relationships.append(current)
            name = _strip_quotes(stripped[13:].strip())
            current = {
                "name": name,
                "fromTable": "",
                "fromColumn": "",
                "fromCardinality": "many",
                "toTable": "",
                "toColumn": "",
                "toCardinality": "one",
                "crossFilteringBehavior": "oneDirection",
                "isActive": True,
            }
            continue

        if current is None:
            continue

        kv = re.match(r"(\w+)\s*:\s*(.*)", stripped)
        if kv:
            key = kv.group(1)
            val = kv.group(2).strip()

            if key == "fromColumn":
                parts = _parse_table_column_ref(val)
                if parts:
                    current["fromTable"] = parts[0]
                    current["fromColumn"] = parts[1]
            elif key == "toColumn":
                parts = _parse_table_column_ref(val)
                if parts:
                    current["toTable"] = parts[0]
                    current["toColumn"] = parts[1]
            elif key == "crossFilteringBehavior":
                current["crossFilteringBehavior"] = val
            elif key == "isActive":
                current["isActive"] = val.lower() != "false"
            elif key == "fromCardinality":
                current["fromCardinality"] = val
            elif key == "toCardinality":
                current["toCardinality"] = val

    if current is not None:
        relationships.append(current)

    return relationships


def _parse_table_column_ref(ref: str) -> tuple[str, str] | None:
    """Parse 'TableName'.'ColumnName' or TableName.ColumnName."""
    m = re.match(r"'?([^'.]+)'?\.'?([^'.]+)'?", ref)
    if m:
        return m.group(1), m.group(2)
    return None


def parse_tmdl_folder(definition_path: Path) -> SemanticModel:
    """Parse a TMDL definition/ folder into a SemanticModel."""
    sm = SemanticModel()

    # database.tmdl
    db_path = definition_path / "database.tmdl"
    if db_path.exists():
        text = db_path.read_text(encoding="utf-8")
        for line in text.splitlines():
            stripped = line.strip()
            m = re.match(r"compatibilityLevel\s*:\s*(\d+)", stripped)
            if m:
                sm.compatibility_level = int(m.group(1))
            if stripped.startswith("database "):
                sm.name = _strip_quotes(stripped[9:].strip())

    # model.tmdl
    model_path = definition_path / "model.tmdl"
    if model_path.exists():
        text = model_path.read_text(encoding="utf-8")
        for line in text.splitlines():
            m = re.match(r"\s*culture\s*:\s*(.+)", line)
            if m:
                sm.culture = m.group(1).strip()

    # tables/
    tables_dir = definition_path / "tables"
    if tables_dir.is_dir():
        for tmdl_file in sorted(tables_dir.glob("*.tmdl")):
            text = tmdl_file.read_text(encoding="utf-8")
            table = _parse_tmdl_table(text)
            if table["name"]:
                sm.tables.append(table)

    # relationships.tmdl
    rel_path = definition_path / "relationships.tmdl"
    if rel_path.exists():
        text = rel_path.read_text(encoding="utf-8")
        sm.relationships = _parse_relationships_tmdl(text)

    # expressions.tmdl
    expr_path = definition_path / "expressions.tmdl"
    if expr_path.exists():
        text = expr_path.read_text(encoding="utf-8")
        sm.expressions = _parse_expressions_tmdl(text)

    return sm


def _parse_expressions_tmdl(text: str) -> list[dict]:
    """Parse expressions.tmdl for named parameters."""
    expressions: list[dict] = []
    current: dict | None = None

    for raw_line in text.splitlines():
        stripped = raw_line.strip()
        if not stripped or stripped.startswith("///"):
            continue

        m = re.match(r"expression\s+(.+?)\s*=\s*(.*)", stripped)
        if m:
            if current is not None:
                expressions.append(current)
            current = {
                "name": _strip_quotes(m.group(1)),
                "expression": m.group(2).strip().strip('"'),
            }
            continue

        if current is not None:
            kv_m = re.match(r"(\w+)\s*:\s*(.*)", stripped)
            if kv_m:
                current[kv_m.group(1)] = kv_m.group(2).strip()

    if current is not None:
        expressions.append(current)

    return expressions
