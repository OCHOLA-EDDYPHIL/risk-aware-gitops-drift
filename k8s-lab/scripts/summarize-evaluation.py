#!/usr/bin/env python3
"""Derive reproducible RADAR formal-evaluation metrics from reviewable evidence."""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import math
import statistics
import sys
from datetime import datetime
from pathlib import Path
from typing import Any


SEVERITY_RANK = {"INFO": 0, "LOW": 1, "MEDIUM": 2, "HIGH": 3, "CRITICAL": 4}


class MetricsError(ValueError):
    pass


def load_object(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as error:
        raise MetricsError(f"invalid JSON: {path}") from error
    if not isinstance(value, dict):
        raise MetricsError(f"JSON object required: {path}")
    return value


def instant(value: Any) -> datetime:
    if not isinstance(value, str) or not value.endswith("Z"):
        raise MetricsError("invalid metric timestamp")
    try:
        return datetime.fromisoformat(value[:-1] + "+00:00")
    except ValueError as error:
        raise MetricsError("invalid metric timestamp") from error


def nearest_rank(values: list[float], percentile: float) -> float | None:
    if not values:
        return None
    ordered = sorted(values)
    return ordered[max(0, math.ceil(percentile * len(ordered)) - 1)]


def complete_explanation(finding: dict[str, Any]) -> bool:
    resource = finding.get("resource")
    change = finding.get("change")
    return (
        isinstance(resource, dict)
        and any(resource.get(field) for field in ("kind", "name"))
        and isinstance(change, dict)
        and isinstance(change.get("operation"), str)
        and isinstance(finding.get("severity"), str)
        and bool(finding.get("reason"))
        and bool(finding.get("recommendation"))
    )


def derive(
    protocol: dict[str, Any], collection_root: Path, protocol_sha256: str | None = None
) -> tuple[list[dict[str, Any]], dict[str, Any]]:
    runs = protocol.get("runs")
    if not isinstance(runs, list) or len(runs) != 80:
        raise MetricsError("protocol must contain 80 declared runs")

    rows: list[dict[str, Any]] = []
    time_to_detect: list[float] = []
    processing_latency: list[float] = []
    detected_security = 0
    false_negatives = 0
    false_positives = 0
    true_positives = 0
    matrix_false_negatives = 0
    true_negatives = 0
    exact_severity = 0
    completed = 0
    evaluable = 0
    complete_explanations = 0
    expected_explanations = 0
    provenance: dict[str, set[str]] = {
        "sourceCommit": set(),
        "scannerSha256": set(),
        "policySha256": set(),
        "riskMatrixSha256": set(),
        "environmentSha256": set(),
    }

    for declaration in runs:
        scenario = declaration["scenario"]
        repetition = declaration["repetition"]
        summary = collection_root / "runs" / scenario / f"run-{repetition:03d}"
        metadata_path = summary / "metadata.json"
        result_path = summary / "radar-result.json"
        if not metadata_path.is_file():
            rows.append({**declaration, "status": "missing", "detected": False})
            if declaration["groundTruth"] == "security":
                false_negatives += 1
            continue

        metadata = load_object(metadata_path)
        if metadata.get("evidenceSchemaVersion") != 4 or metadata.get("evidenceTier") != "formally-evaluated":
            raise MetricsError(f"run is not schema-v4 formal evidence: {declaration['runId']}")
        if metadata.get("protocolId") != protocol.get("protocolId"):
            raise MetricsError(f"protocol identity mismatch: {declaration['runId']}")
        if protocol_sha256 is not None and metadata.get("protocolSha256") != protocol_sha256:
            raise MetricsError(f"protocol checksum mismatch: {declaration['runId']}")
        if metadata.get("declaredRunId") != declaration["runId"]:
            raise MetricsError(f"run identity mismatch: {declaration['runId']}")
        for field, values in provenance.items():
            value = metadata.get(field)
            if not isinstance(value, str) or not value:
                raise MetricsError(f"missing formal provenance {field}: {declaration['runId']}")
            values.add(value)
        status = metadata.get("status")
        findings: list[dict[str, Any]] = []
        if result_path.is_file():
            result = load_object(result_path)
            value = result.get("findings")
            if not isinstance(value, list):
                raise MetricsError(f"invalid findings: {declaration['runId']}")
            findings = [finding for finding in value if isinstance(finding, dict)]
            evaluable += 1

        expected = next(
            (finding for finding in findings if finding.get("ruleId") == declaration["expectedRule"]),
            None,
        )
        detected = expected is not None
        observed_severity = expected.get("severity") if expected else None
        if status == "completed":
            completed += 1
            if observed_severity == declaration["expectedSeverity"]:
                exact_severity += 1
            expected_explanations += 1
            if expected is not None and complete_explanation(expected):
                complete_explanations += 1
            try:
                time_to_detect.append(
                    (instant(metadata["radarCompletedAt"]) - instant(metadata["mutationAt"])).total_seconds()
                )
                processing_latency.append(
                    (instant(metadata["radarCompletedAt"]) - instant(metadata["observedAt"])).total_seconds()
                )
            except (KeyError, MetricsError):
                pass

        if declaration["groundTruth"] == "security":
            if detected:
                detected_security += 1
            else:
                false_negatives += 1
            elevated = any(SEVERITY_RANK.get(str(finding.get("severity")), -1) >= SEVERITY_RANK["MEDIUM"] for finding in findings)
            if elevated:
                true_positives += 1
            elif result_path.is_file():
                matrix_false_negatives += 1
        else:
            elevated = any(SEVERITY_RANK.get(str(finding.get("severity")), -1) >= SEVERITY_RANK["MEDIUM"] for finding in findings)
            if elevated:
                false_positives += 1
            elif findings:
                true_negatives += 1

        rows.append(
            {
                **declaration,
                "status": status,
                "detected": detected,
                "observedSeverity": observed_severity,
                "baselineResetVerified": metadata.get("baselineResetVerified"),
            }
        )

    for field, values in provenance.items():
        if len(values) > 1:
            raise MetricsError(f"formal corpus mixes {field} values")
    metrics = {
        "protocolId": protocol.get("protocolId"),
        "declaredRuns": len(runs),
        "completedRuns": completed,
        "evaluableRuns": evaluable,
        "missingOrIncompleteRuns": len(runs) - completed,
        "securityRuns": 70,
        "controlRuns": 10,
        "detectedSecurityRuns": detected_security,
        "falseNegatives": false_negatives,
        "falsePositives": false_positives,
        "detectionAccuracy": detected_security / 70,
        "falsePositiveRatePerDeclaredControl": false_positives / 10,
        "exactSeverityAccuracy": exact_severity / completed if completed else None,
        "explanationCompleteness": complete_explanations / expected_explanations if expected_explanations else None,
        "confusionMatrixEvaluable": {
            "truePositive": true_positives,
            "falseNegative": matrix_false_negatives,
            "falsePositive": false_positives,
            "trueNegative": true_negatives,
        },
        "timeToDetectSeconds": {
            "count": len(time_to_detect),
            "median": statistics.median(time_to_detect) if time_to_detect else None,
            "p95NearestRank": nearest_rank(time_to_detect, 0.95),
        },
        "processingLatencySeconds": {
            "count": len(processing_latency),
            "median": statistics.median(processing_latency) if processing_latency else None,
            "p95NearestRank": nearest_rank(processing_latency, 0.95),
        },
        "freezeProvenance": {
            field: next(iter(values)) if values else None for field, values in provenance.items()
        },
    }
    return rows, metrics


def write_outputs(rows: list[dict[str, Any]], metrics: dict[str, Any], output: Path) -> None:
    output.mkdir(parents=True, exist_ok=False)
    (output / "metrics.json").write_text(json.dumps(metrics, indent=2) + "\n", encoding="utf-8")
    fields = [
        "runId",
        "scenario",
        "repetition",
        "groundTruth",
        "expectedRule",
        "expectedSeverity",
        "expectedScore",
        "expectedPath",
        "status",
        "detected",
        "observedSeverity",
        "baselineResetVerified",
    ]
    with (output / "run-accounting.csv").open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fields, extrasaction="ignore", lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--protocol-file", required=True, type=Path)
    parser.add_argument("--collection-dir", required=True, type=Path)
    parser.add_argument("--output-dir", required=True, type=Path)
    args = parser.parse_args()
    protocol = load_object(args.protocol_file)
    protocol_sha256 = hashlib.sha256(args.protocol_file.read_bytes()).hexdigest()
    rows, metrics = derive(protocol, args.collection_dir, protocol_sha256)
    write_outputs(rows, metrics, args.output_dir)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except MetricsError as error:
        print(f"metric derivation failed: {error}", file=sys.stderr)
        raise SystemExit(1)
