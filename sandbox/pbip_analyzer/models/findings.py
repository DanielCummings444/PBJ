"""Data models for PBIP analysis findings."""

from __future__ import annotations

import dataclasses as dc
import enum
from typing import Any


class Severity(enum.Enum):
    """Issue severity levels."""

    CRITICAL = "critical"
    HIGH = "high"
    MEDIUM = "medium"
    LOW = "low"
    INFO = "info"


class Category(enum.Enum):
    """Issue categories."""

    PERFORMANCE = "Performance"
    DATA_MODELING = "Data Modeling"
    DAX_QUALITY = "DAX Quality"
    RELATIONSHIPS = "Relationships"
    REPORT_DESIGN = "Report Design"
    BEST_PRACTICES = "Best Practices"
    SECURITY = "Security"
    DOCUMENTATION = "Documentation"
    MAINTENANCE = "Maintenance"


@dc.dataclass
class Finding:
    """A single analysis finding."""

    id: str
    title: str
    description: str
    severity: Severity
    category: Category
    affected_object: str
    recommendation: str
    details: dict[str, Any] = dc.field(default_factory=dict)

    def to_dict(self) -> dict[str, Any]:
        return {
            "id": self.id,
            "title": self.title,
            "description": self.description,
            "severity": self.severity.value,
            "category": self.category.value,
            "affected_object": self.affected_object,
            "recommendation": self.recommendation,
            "details": self.details,
        }


@dc.dataclass
class QuantitativeMetric:
    """A single quantitative metric."""

    name: str
    value: float | int | str
    unit: str = ""
    benchmark: str = ""
    status: str = ""  # "good", "warning", "critical"

    def to_dict(self) -> dict[str, Any]:
        return {
            "name": self.name,
            "value": self.value,
            "unit": self.unit,
            "benchmark": self.benchmark,
            "status": self.status,
        }


@dc.dataclass
class SemanticModel:
    """Parsed semantic model representation."""

    name: str = ""
    compatibility_level: int = 0
    culture: str = ""
    tables: list[dict[str, Any]] = dc.field(default_factory=list)
    relationships: list[dict[str, Any]] = dc.field(default_factory=list)
    roles: list[dict[str, Any]] = dc.field(default_factory=list)
    perspectives: list[dict[str, Any]] = dc.field(default_factory=list)
    data_sources: list[dict[str, Any]] = dc.field(default_factory=list)
    expressions: list[dict[str, Any]] = dc.field(default_factory=list)

    @property
    def all_columns(self) -> list[dict[str, Any]]:
        cols = []
        for table in self.tables:
            for col in table.get("columns", []):
                cols.append({**col, "_table": table["name"]})
        return cols

    @property
    def all_measures(self) -> list[dict[str, Any]]:
        measures = []
        for table in self.tables:
            for m in table.get("measures", []):
                measures.append({**m, "_table": table["name"]})
        return measures

    @property
    def all_calculated_columns(self) -> list[dict[str, Any]]:
        return [c for c in self.all_columns if c.get("type") == "calculated"]

    @property
    def all_hierarchies(self) -> list[dict[str, Any]]:
        hierarchies = []
        for table in self.tables:
            for h in table.get("hierarchies", []):
                hierarchies.append({**h, "_table": table["name"]})
        return hierarchies


@dc.dataclass
class ReportStructure:
    """Parsed report structure."""

    name: str = ""
    pages: list[dict[str, Any]] = dc.field(default_factory=list)
    visuals: list[dict[str, Any]] = dc.field(default_factory=list)
    bookmarks: list[dict[str, Any]] = dc.field(default_factory=list)
    filters: list[dict[str, Any]] = dc.field(default_factory=list)
    theme: dict[str, Any] = dc.field(default_factory=dict)
    format_version: str = ""


@dc.dataclass
class AnalysisResult:
    """Complete analysis result combining all outputs."""

    project_path: str
    model: SemanticModel | None = None
    report: ReportStructure | None = None
    findings: list[Finding] = dc.field(default_factory=list)
    metrics: list[QuantitativeMetric] = dc.field(default_factory=list)

    def findings_by_severity(self) -> dict[str, list[Finding]]:
        result: dict[str, list[Finding]] = {}
        for f in self.findings:
            result.setdefault(f.severity.value, []).append(f)
        return result

    def findings_by_category(self) -> dict[str, list[Finding]]:
        result: dict[str, list[Finding]] = {}
        for f in self.findings:
            result.setdefault(f.category.value, []).append(f)
        return result

    def summary_counts(self) -> dict[str, int]:
        counts = {s.value: 0 for s in Severity}
        for f in self.findings:
            counts[f.severity.value] += 1
        return counts
