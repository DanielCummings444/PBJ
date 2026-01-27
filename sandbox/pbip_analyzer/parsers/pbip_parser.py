"""Top-level PBIP project parser.

Discovers the project structure and dispatches to the appropriate
format-specific parsers (model.bim vs TMDL, PBIR vs PBIR-Legacy).
"""

from __future__ import annotations

import json
from pathlib import Path

from pbip_analyzer.models.findings import (
    AnalysisResult,
    ReportStructure,
    SemanticModel,
)
from pbip_analyzer.parsers.model_bim_parser import parse_model_bim
from pbip_analyzer.parsers.report_parser import parse_report_folder
from pbip_analyzer.parsers.tmdl_parser import parse_tmdl_folder


def discover_project(root: Path) -> dict:
    """Discover the PBIP project layout starting from *root*.

    Returns a dict with keys:
        pbip_file, semantic_model_dir, report_dir, model_format
    """
    root = root.resolve()

    # Find .pbip entry point
    pbip_files = list(root.glob("*.pbip"))
    pbip_file = pbip_files[0] if pbip_files else None

    # Find SemanticModel folder
    sm_dirs = list(root.glob("*.SemanticModel"))
    if not sm_dirs:
        sm_dirs = list(root.glob("*.Dataset"))
    sm_dir = sm_dirs[0] if sm_dirs else None

    # Find Report folder
    rpt_dirs = list(root.glob("*.Report"))
    rpt_dir = rpt_dirs[0] if rpt_dirs else None

    # Determine model format
    model_format = "none"
    if sm_dir:
        if (sm_dir / "definition").is_dir():
            model_format = "tmdl"
        elif (sm_dir / "model.bim").exists():
            model_format = "bim"

    return {
        "pbip_file": pbip_file,
        "semantic_model_dir": sm_dir,
        "report_dir": rpt_dir,
        "model_format": model_format,
    }


def parse_project(root: Path) -> AnalysisResult:
    """Parse an entire PBIP project and return an AnalysisResult shell."""
    project = discover_project(root)
    result = AnalysisResult(project_path=str(root))

    # Parse semantic model
    sm_dir = project["semantic_model_dir"]
    if sm_dir:
        fmt = project["model_format"]
        if fmt == "tmdl":
            result.model = parse_tmdl_folder(sm_dir / "definition")
        elif fmt == "bim":
            result.model = parse_model_bim(sm_dir / "model.bim")

    # Parse report
    rpt_dir = project["report_dir"]
    if rpt_dir:
        result.report = parse_report_folder(rpt_dir)

    return result
