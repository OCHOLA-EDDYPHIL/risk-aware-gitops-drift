#!/usr/bin/env python3
"""Validate one schema-v3 RADAR run and its cross-artifact evidence chain."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from datetime import datetime
from pathlib import Path
from typing import Any


ALLOWED_FILES = {
    "metadata.json",
    "environment.json",
    "mutation.json",
    "argocd-observation.json",
    "argocd-application.json",
    "argocd-managed-resources.json",
    "scan-input.json",
    "radar-result.json",
    "reset.json",
}
SCENARIOS = {
    "rbac-wildcard": ("RADAR-RBAC-WILDCARD", "CRITICAL", "/rules/0/apiGroups/0"),
    "networkpolicy-removal": ("RADAR-NETPOL-REMOVED", "HIGH", ""),
    "privileged-container": (
        "RADAR-WORKLOAD-PRIVILEGED",
        "CRITICAL",
        "/spec/template/spec/containers/0/securityContext/privileged",
    ),
    "hostpath-addition": (
        "RADAR-VOLUME-HOSTPATH",
        "HIGH",
        "/spec/template/spec/volumes/0/hostPath",
    ),
    "service-exposure": ("RADAR-SERVICE-EXPOSURE", "HIGH", "/spec/type"),
    "unsafe-image-tag": (
        "RADAR-IMAGE-LATEST",
        "MEDIUM",
        "/spec/template/spec/containers/0/image",
    ),
    "secret-reference": (
        "RADAR-SECRET-REFERENCE",
        "MEDIUM",
        "/spec/template/spec/containers/0/env/0/valueFrom/secretKeyRef/name",
    ),
    "metadata-only": (
        "RADAR-METADATA-ONLY",
        "LOW",
        "/metadata/labels/app.kubernetes.io~1part-of",
    ),
}
SHA_PATTERN = re.compile(r"^[0-9a-f]{64}$")
COMMIT_PATTERN = re.compile(r"^[0-9a-f]{40}$")
IDENTIFIER_PATTERN = re.compile(r"^[a-z0-9][a-z0-9._-]*$")


class EvidenceValidationError(ValueError):
    pass


def fail(message: str) -> None:
    raise EvidenceValidationError(message)


def reject_duplicates(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            fail(f"duplicate key in JSON object: {key}")
        result[key] = value
    return result


def load(path: Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"), object_pairs_hook=reject_duplicates)
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as error:
        raise EvidenceValidationError(f"invalid JSON artifact: {path.name}") from error


def require(condition: bool, message: str) -> None:
    if not condition:
        fail(message)


def timestamp(value: Any, field: str) -> datetime:
    require(isinstance(value, str) and value.endswith("Z"), f"invalid timestamp: {field}")
    try:
        return datetime.fromisoformat(value[:-1] + "+00:00")
    except ValueError as error:
        raise EvidenceValidationError(f"invalid timestamp: {field}") from error


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def validate_run(root: Path) -> None:
    require(root.is_dir() and not root.is_symlink(), "run directory is unsafe")
    entries = list(root.iterdir())
    for entry in entries:
        require(entry.name in ALLOWED_FILES, f"unexpected artifact: {entry.name}")
        require(entry.is_file() and not entry.is_symlink(), f"unsafe artifact: {entry.name}")
        require(entry.stat().st_nlink == 1, f"hard-linked artifact: {entry.name}")
    files = {entry.name: entry for entry in entries}
    require("metadata.json" in files and "environment.json" in files, "metadata and environment are required")

    metadata = load(files["metadata.json"])
    environment = load(files["environment.json"])
    require(isinstance(metadata, dict) and isinstance(environment, dict), "metadata and environment must be objects")
    require(metadata.get("evidenceSchemaVersion") == 3, "schema version 3 is required")
    collection = metadata.get("collectionId")
    scenario = metadata.get("scenario")
    repetition = metadata.get("repetition")
    status = metadata.get("status")
    tier = metadata.get("evidenceTier")
    source_commit = metadata.get("sourceCommit")
    require(isinstance(collection, str) and IDENTIFIER_PATTERN.fullmatch(collection) is not None, "invalid collection identifier")
    require(scenario in SCENARIOS, "unknown scenario")
    require(type(repetition) is int and repetition > 0, "invalid repetition")
    require(status in {"completed", "failed"}, "invalid status")
    require(tier == ("controlled-lab-observed" if status == "completed" else "implemented"), "status and evidence tier disagree")
    require(isinstance(source_commit, str) and COMMIT_PATTERN.fullmatch(source_commit) is not None, "invalid source commit")
    for field in ("scannerSha256", "policySha256", "environmentSha256"):
        require(isinstance(metadata.get(field), str) and SHA_PATTERN.fullmatch(metadata[field]) is not None, f"invalid hash: {field}")
    require(metadata["environmentSha256"] == sha256(files["environment.json"]), "environment hash mismatch")
    require(environment.get("collectionId") == collection, "environment collection mismatch")
    require(environment.get("source", {}).get("commit") == source_commit, "environment commit mismatch")
    require(metadata.get("argoTargetRevision") == source_commit, "target revision mismatch")
    require(metadata.get("argoSynchronizedRevision") == source_commit, "synchronized revision mismatch")
    require(metadata.get("argoOperationRevision") == source_commit, "operation revision mismatch")
    require(metadata.get("argoOperationPhase") == "Succeeded", "operation phase mismatch")
    expected_rule, expected_severity, expected_path = SCENARIOS[scenario]
    require(metadata.get("expectedRule") == expected_rule, "expected rule mismatch")
    require(metadata.get("expectedSeverity") == expected_severity, "expected severity mismatch")
    started = timestamp(metadata.get("startedAt"), "startedAt")
    captured = timestamp(environment.get("capturedAt"), "environment.capturedAt")
    require(captured <= started, "environment was captured after the run started")

    if status == "failed":
        timestamp(metadata.get("failedAt"), "failedAt")
        require(isinstance(metadata.get("failureStage"), str), "failed run lacks failure stage")
        require(type(metadata.get("baselineResetVerified")) is bool, "failed run lacks reset status")
        if metadata["baselineResetVerified"]:
            require("reset.json" in files, "verified failed-run reset lacks reset artifact")
            reset = load(files["reset.json"])
            require(reset.get("declaredBaselineVerified") is True, "failed-run reset is not verified")
        return

    required = {
        "mutation.json",
        "argocd-observation.json",
        "argocd-application.json",
        "argocd-managed-resources.json",
        "scan-input.json",
        "radar-result.json",
        "reset.json",
    }
    require(required.issubset(files), "completed run is missing required artifacts")
    mutation = load(files["mutation.json"])
    observation = load(files["argocd-observation.json"])
    application = load(files["argocd-application.json"])
    managed = load(files["argocd-managed-resources.json"])
    scan_input = load(files["scan-input.json"])
    result = load(files["radar-result.json"])
    reset = load(files["reset.json"])
    require(mutation.get("collectionId") == collection and mutation.get("scenario") == scenario, "mutation identity mismatch")
    require(observation.get("application") == "radar-lab" and observation.get("project") == "radar", "observation application mismatch")
    require(observation.get("targetRevision") == source_commit, "observation target mismatch")
    require(observation.get("synchronizedRevision") == source_commit, "observation synchronized revision mismatch")
    require(observation.get("operationRevision") == source_commit and observation.get("operationPhase") == "Succeeded", "observation operation mismatch")
    require(observation.get("syncStatus") == "OutOfSync", "observation is not OutOfSync")
    require(application.get("spec", {}).get("source", {}).get("targetRevision") == source_commit, "captured Application target mismatch")
    require(application.get("status", {}).get("sync", {}).get("revision") == source_commit, "captured Application revision mismatch")
    require(application.get("metadata", {}).get("resourceVersion") == metadata.get("applicationResourceVersion"), "Application resource version mismatch")
    require(isinstance(managed, dict) and isinstance(managed.get("items"), list), "managed-resource response is invalid")
    require(type(metadata.get("captureAttempt")) is int and 1 <= metadata["captureAttempt"] <= 5, "invalid capture attempt")
    require(scan_input == {"application": application, "managedResources": managed}, "scan input does not equal captured artifacts")
    require(metadata.get("capturedInputSha256") == sha256(files["scan-input.json"]), "scan-input hash mismatch")
    require(result.get("application") == "radar-lab" and result.get("syncStatus") == "OutOfSync", "RADAR result application mismatch")
    findings = result.get("findings")
    require(isinstance(findings, list), "RADAR findings are invalid")
    require(
        any(
            finding.get("ruleId") == expected_rule
            and finding.get("severity") == expected_severity
            and finding.get("change", {}).get("path") == expected_path
            for finding in findings
            if isinstance(finding, dict)
        ),
        "expected decision and field path are absent",
    )
    require(metadata.get("baselineResetVerified") is True, "completed run lacks verified reset")
    require(reset.get("declaredBaselineVerified") is True, "reset baseline is not verified")
    require(reset.get("targetRevision") == source_commit and reset.get("operationRevision") == source_commit, "reset revision mismatch")
    require(reset.get("operationPhase") == "Succeeded", "reset operation did not succeed")
    require(reset.get("syncStatus") == "Synced" and reset.get("healthStatus") == "Healthy", "reset state mismatch")
    require(isinstance(reset.get("operationInitiator"), str) and reset["operationInitiator"].startswith("radar-reset-"), "reset initiator mismatch")

    chronology = [
        started,
        timestamp(mutation.get("startedAt"), "mutation.startedAt"),
        timestamp(mutation.get("completedAt"), "mutation.completedAt"),
        timestamp(observation.get("observedAt"), "observation.observedAt"),
        timestamp(metadata.get("radarCompletedAt"), "radarCompletedAt"),
        timestamp(reset.get("startedAt"), "reset.startedAt"),
        timestamp(reset.get("completedAt"), "reset.completedAt"),
        timestamp(metadata.get("completedAt"), "completedAt"),
    ]
    require(chronology == sorted(chronology), "run timestamps are not chronological")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("run_dir", type=Path)
    args = parser.parse_args()
    try:
        validate_run(args.run_dir.resolve())
    except EvidenceValidationError as error:
        print(f"evidence validation failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
