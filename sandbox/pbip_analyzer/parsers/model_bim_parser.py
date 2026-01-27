"""Parser for model.bim (TMSL JSON) files."""

from __future__ import annotations

import json
from pathlib import Path

from pbip_analyzer.models.findings import SemanticModel


def parse_model_bim(path: Path) -> SemanticModel:
    """Parse a model.bim file into a SemanticModel."""
    with open(path, encoding="utf-8") as f:
        raw = json.load(f)

    model_data = raw.get("model", raw)

    sm = SemanticModel(
        name=raw.get("name", model_data.get("name", "")),
        compatibility_level=raw.get(
            "compatibilityLevel",
            model_data.get("compatibilityLevel", 0),
        ),
        culture=model_data.get("culture", ""),
        data_sources=model_data.get("dataSources", []),
        roles=model_data.get("roles", []),
        perspectives=model_data.get("perspectives", []),
        expressions=model_data.get("expressions", []),
    )

    for tbl in model_data.get("tables", []):
        table = {
            "name": tbl.get("name", ""),
            "isHidden": tbl.get("isHidden", False),
            "description": tbl.get("description", ""),
            "dataCategory": tbl.get("dataCategory", ""),
            "columns": [],
            "measures": [],
            "partitions": tbl.get("partitions", []),
            "hierarchies": tbl.get("hierarchies", []),
            "annotations": tbl.get("annotations", []),
        }

        for col in tbl.get("columns", []):
            table["columns"].append({
                "name": col.get("name", ""),
                "type": col.get("type", "data"),
                "dataType": col.get("dataType", ""),
                "isHidden": col.get("isHidden", False),
                "isKey": col.get("isKey", False),
                "isNullable": col.get("isNullable", True),
                "sourceColumn": col.get("sourceColumn", ""),
                "expression": col.get("expression", ""),
                "summarizeBy": col.get("summarizeBy", "default"),
                "sortByColumn": col.get("sortByColumn", ""),
                "displayFolder": col.get("displayFolder", ""),
                "formatString": col.get("formatString", ""),
                "annotations": col.get("annotations", []),
            })

        for meas in tbl.get("measures", []):
            table["measures"].append({
                "name": meas.get("name", ""),
                "expression": meas.get("expression", ""),
                "description": meas.get("description", ""),
                "formatString": meas.get("formatString", ""),
                "isHidden": meas.get("isHidden", False),
                "displayFolder": meas.get("displayFolder", ""),
                "kpi": meas.get("kpi"),
                "annotations": meas.get("annotations", []),
            })

        sm.tables.append(table)

    for rel in model_data.get("relationships", []):
        sm.relationships.append({
            "name": rel.get("name", ""),
            "fromTable": rel.get("fromTable", ""),
            "fromColumn": rel.get("fromColumn", ""),
            "fromCardinality": rel.get("fromCardinality", "many"),
            "toTable": rel.get("toTable", ""),
            "toColumn": rel.get("toColumn", ""),
            "toCardinality": rel.get("toCardinality", "one"),
            "crossFilteringBehavior": rel.get(
                "crossFilteringBehavior", "oneDirection"
            ),
            "isActive": rel.get("isActive", True),
            "securityFilteringBehavior": rel.get(
                "securityFilteringBehavior", "oneDirection"
            ),
        })

    return sm
