"""Parser for Power BI report structures (PBIR and PBIR-Legacy)."""

from __future__ import annotations

import json
from pathlib import Path

from pbip_analyzer.models.findings import ReportStructure


def parse_report_folder(report_path: Path) -> ReportStructure:
    """Parse a Report folder into a ReportStructure.

    Supports both PBIR-Legacy (single report.json) and PBIR Enhanced
    (definition/ folder with decomposed JSON files).
    """
    rs = ReportStructure()
    rs.name = report_path.name

    # Determine format from definition.pbir
    pbir_file = report_path / "definition.pbir"
    if pbir_file.exists():
        pbir = json.loads(pbir_file.read_text(encoding="utf-8"))
        rs.format_version = pbir.get("version", "")

    # PBIR Enhanced: definition/ folder
    defn_dir = report_path / "definition"
    if defn_dir.is_dir():
        _parse_pbir_enhanced(defn_dir, rs)
    else:
        # PBIR-Legacy: single report.json
        legacy_report = report_path / "report.json"
        if legacy_report.exists():
            _parse_pbir_legacy(legacy_report, rs)

    return rs


def _parse_pbir_enhanced(defn_dir: Path, rs: ReportStructure) -> None:
    """Parse the PBIR Enhanced definition/ folder."""
    # Report-level metadata
    report_json = defn_dir / "report.json"
    if report_json.exists():
        data = json.loads(report_json.read_text(encoding="utf-8"))
        rs.theme = data.get("themeCollection", {})
        rs.filters = data.get("filters", [])

    # Pages
    pages_dir = defn_dir / "pages"
    if pages_dir.is_dir():
        pages_meta = pages_dir / "pages.json"
        if pages_meta.exists():
            meta = json.loads(pages_meta.read_text(encoding="utf-8"))
            rs.pages = meta.get("pages", meta.get("pageOrder", []))

        for page_dir in sorted(pages_dir.iterdir()):
            if not page_dir.is_dir():
                continue
            page_json = page_dir / "page.json"
            if page_json.exists():
                page_data = json.loads(page_json.read_text(encoding="utf-8"))
                page_data["_id"] = page_dir.name
                # Count visuals
                visuals_dir = page_dir / "visuals"
                page_visuals = []
                if visuals_dir.is_dir():
                    for vis_dir in sorted(visuals_dir.iterdir()):
                        if not vis_dir.is_dir():
                            continue
                        vis_json = vis_dir / "visual.json"
                        if vis_json.exists():
                            vis_data = json.loads(
                                vis_json.read_text(encoding="utf-8")
                            )
                            vis_data["_id"] = vis_dir.name
                            vis_data["_page"] = page_data.get(
                                "displayName", page_dir.name
                            )
                            page_visuals.append(vis_data)
                page_data["_visuals"] = page_visuals
                rs.visuals.extend(page_visuals)

                # Update or append page
                found = False
                for idx, p in enumerate(rs.pages):
                    if isinstance(p, dict) and p.get("_id") == page_dir.name:
                        rs.pages[idx] = {**p, **page_data}
                        found = True
                        break
                if not found:
                    rs.pages.append(page_data)

    # Bookmarks
    bookmarks_dir = defn_dir / "bookmarks"
    if bookmarks_dir.is_dir():
        for bm_file in sorted(bookmarks_dir.glob("*.bookmark.json")):
            bm = json.loads(bm_file.read_text(encoding="utf-8"))
            rs.bookmarks.append(bm)


def _parse_pbir_legacy(report_json_path: Path, rs: ReportStructure) -> None:
    """Parse a single legacy report.json.

    Legacy report.json files have an internal structure that varies
    across PBI Desktop versions.  We extract what we can.
    """
    try:
        data = json.loads(report_json_path.read_text(encoding="utf-8"))
    except (json.JSONDecodeError, UnicodeDecodeError):
        return

    rs.format_version = "legacy"

    # Some legacy formats store sections (pages) as a list
    sections = data.get("sections", [])
    for sec in sections:
        page = {
            "displayName": sec.get("displayName", sec.get("name", "")),
            "name": sec.get("name", ""),
            "width": sec.get("width", 0),
            "height": sec.get("height", 0),
            "_visuals": [],
        }

        for vc in sec.get("visualContainers", []):
            config_str = vc.get("config", "{}")
            try:
                config = json.loads(config_str) if isinstance(config_str, str) else config_str
            except json.JSONDecodeError:
                config = {}

            visual = {
                "position": {
                    "x": vc.get("x", 0),
                    "y": vc.get("y", 0),
                    "width": vc.get("width", 0),
                    "height": vc.get("height", 0),
                    "z": vc.get("z", 0),
                },
                "_page": page["displayName"],
            }

            single_visual = config.get("singleVisual", {})
            if single_visual:
                visual["visual"] = {
                    "visualType": single_visual.get("visualType", ""),
                }

            page["_visuals"].append(visual)
            rs.visuals.append(visual)

        rs.pages.append(page)
