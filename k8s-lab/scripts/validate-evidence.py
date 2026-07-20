#!/usr/bin/env python3
"""Validate a RADAR qualification or protocol-bound formal evidence chain."""

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
FORMAL_EXPECTATIONS = {
    "rbac-wildcard": ("RADAR-RBAC-WILDCARD", "CRITICAL", 100, "/rules/0/apiGroups/0", "security"),
    "networkpolicy-removal": ("RADAR-NETPOL-REMOVED", "HIGH", 64, "", "security"),
    "privileged-container": ("RADAR-WORKLOAD-PRIVILEGED", "CRITICAL", 100, "/spec/template/spec/containers/0/securityContext/privileged", "security"),
    "hostpath-addition": ("RADAR-VOLUME-HOSTPATH", "HIGH", 60, "/spec/template/spec/volumes/0/hostPath", "security"),
    "service-exposure": ("RADAR-SERVICE-EXPOSURE", "HIGH", 64, "/spec/type", "security"),
    "unsafe-image-tag": ("RADAR-IMAGE-LATEST", "MEDIUM", 36, "/spec/template/spec/containers/0/image", "security"),
    "secret-reference": ("RADAR-SECRET-REFERENCE", "MEDIUM", 32, "/spec/template/spec/containers/0/env/0/valueFrom/secretKeyRef/name", "security"),
    "metadata-only": ("RADAR-METADATA-ONLY", "LOW", 4, "/metadata/labels/app.kubernetes.io~1part-of", "control"),
}
SHA_PATTERN = re.compile(r"^[0-9a-f]{64}$")
COMMIT_PATTERN = re.compile(r"^[0-9a-f]{40}$")
IDENTIFIER_PATTERN = re.compile(r"^[a-z0-9][a-z0-9._-]*$")
FAILED_STAGE_ARTIFACTS = {
    "prepare-mutation": set(),
    "inject-drift": {"reset.json"},
    "observe-argocd": {"mutation.json", "reset.json"},
    "capture-managed-resources": {"mutation.json", "reset.json"},
    "scan-radar": {
        "mutation.json",
        "argocd-observation.json",
        "argocd-application.json",
        "argocd-managed-resources.json",
        "scan-input.json",
        "reset.json",
    },
    "verify-decision": {
        "mutation.json",
        "argocd-observation.json",
        "argocd-application.json",
        "argocd-managed-resources.json",
        "scan-input.json",
        "radar-result.json",
        "reset.json",
    },
    "reset-baseline": {
        "mutation.json",
        "argocd-observation.json",
        "argocd-application.json",
        "argocd-managed-resources.json",
        "scan-input.json",
        "radar-result.json",
        "reset.json",
    },
}


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


def validate_run(root: Path, protocol_file: Path | None = None) -> None:
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
    schema_version = metadata.get("evidenceSchemaVersion")
    require(schema_version in {3, 4}, "evidence schema version 3 or 4 is required")
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
    expected_tier = "formally-evaluated" if schema_version == 4 else ("controlled-lab-observed" if status == "completed" else "implemented")
    require(tier == expected_tier, "status, schema, and evidence tier disagree")
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
    if schema_version == 4:
        require(protocol_file is not None, "schema-v4 evidence requires its frozen protocol")
        require(protocol_file.is_file() and not protocol_file.is_symlink(), "formal protocol is unsafe")
        protocol = load(protocol_file)
        require(isinstance(protocol, dict), "formal protocol must be an object")
        protocol_id = metadata.get("protocolId")
        declared_run_id = metadata.get("declaredRunId")
        formal_rule, formal_severity, formal_score, formal_path, formal_truth = FORMAL_EXPECTATIONS[scenario]
        require(isinstance(protocol_id, str) and IDENTIFIER_PATTERN.fullmatch(protocol_id) is not None, "invalid protocol identifier")
        require(isinstance(declared_run_id, str) and IDENTIFIER_PATTERN.fullmatch(declared_run_id) is not None, "invalid declared run identifier")
        for field in ("protocolSha256", "riskMatrixSha256"):
            require(isinstance(metadata.get(field), str) and SHA_PATTERN.fullmatch(metadata[field]) is not None, f"invalid hash: {field}")
        require(metadata["protocolSha256"] == sha256(protocol_file), "formal protocol hash mismatch")
        require(protocol.get("protocolVersion") == 1 and protocol.get("evidenceSchemaVersion") == 4, "formal protocol version mismatch")
        require(protocol.get("protocolId") == protocol_id and protocol.get("collectionId") == collection, "formal protocol identity mismatch")
        require(protocol.get("declaredRunCount") == 80 and isinstance(protocol.get("runs"), list) and len(protocol["runs"]) == 80, "formal protocol must declare 80 runs")
        require(
            metadata.get("expectedRule") == formal_rule
            and metadata.get("expectedSeverity") == formal_severity
            and metadata.get("expectedScore") == formal_score
            and metadata.get("expectedPath") == formal_path
            and metadata.get("groundTruth") == formal_truth,
            "formal ground truth mismatch",
        )
        declared = [
            run
            for run in protocol.get("runs", [])
            if isinstance(run, dict)
            and run.get("scenario") == scenario
            and run.get("repetition") == repetition
        ]
        require(len(declared) == 1 and declared[0].get("runId") == declared_run_id, "formal run is not uniquely declared")
        for field in ("expectedRule", "expectedSeverity", "expectedScore", "expectedPath", "groundTruth"):
            require(declared[0].get(field) == metadata.get(field), f"formal declaration mismatch: {field}")
    started = timestamp(metadata.get("startedAt"), "startedAt")
    captured = timestamp(environment.get("capturedAt"), "environment.capturedAt")
    require(captured <= started, "environment was captured after the run started")

    if status == "failed":
        failed_at = timestamp(metadata.get("failedAt"), "failedAt")
        failure_stage = metadata.get("failureStage")
        require(failure_stage in FAILED_STAGE_ARTIFACTS, "failed run has unknown failure stage")
        require(type(metadata.get("exitCode")) is int and metadata["exitCode"] != 0, "failed run lacks a nonzero exit code")
        require(type(metadata.get("baselineResetVerified")) is bool, "failed run lacks reset status")
        require(started <= failed_at, "failedAt precedes startedAt")
        require(FAILED_STAGE_ARTIFACTS[failure_stage].issubset(files), "failed run lacks artifacts required by its failure stage")
        mutation_completed = None
        if "mutation.json" in files:
            mutation = load(files["mutation.json"])
            require(isinstance(mutation, dict), "failed-run mutation is invalid")
            require(mutation.get("collectionId") == collection and mutation.get("scenario") == scenario, "failed-run mutation identity mismatch")
            mutation_started = timestamp(mutation.get("startedAt"), "mutation.startedAt")
            mutation_completed = timestamp(mutation.get("completedAt"), "mutation.completedAt")
            require(started <= mutation_started <= mutation_completed <= failed_at, "failed-run mutation chronology mismatch")
        if "argocd-observation.json" in files:
            observation = load(files["argocd-observation.json"])
            require(isinstance(observation, dict), "failed-run observation is invalid")
            require(observation.get("application") == "radar-lab" and observation.get("project") == "radar", "failed-run observation application mismatch")
            require(observation.get("targetRevision") == source_commit, "failed-run observation target mismatch")
            require(observation.get("synchronizedRevision") == source_commit, "failed-run observation revision mismatch")
            require(observation.get("operationRevision") == source_commit and observation.get("operationPhase") == "Succeeded", "failed-run observation operation mismatch")
            require(observation.get("syncStatus") == "OutOfSync", "failed-run observation is not OutOfSync")
            observation_at = timestamp(observation.get("observedAt"), "observation.observedAt")
            require((mutation_completed or started) <= observation_at <= failed_at, "failed-run observation chronology mismatch")
        application = load(files["argocd-application.json"]) if "argocd-application.json" in files else None
        managed = load(files["argocd-managed-resources.json"]) if "argocd-managed-resources.json" in files else None
        if application is not None:
            require(isinstance(application, dict), "failed-run Application is invalid")
            require(application.get("spec", {}).get("source", {}).get("targetRevision") == source_commit, "failed-run Application target mismatch")
            require(application.get("status", {}).get("sync", {}).get("revision") == source_commit, "failed-run Application revision mismatch")
            require(application.get("status", {}).get("operationState", {}).get("syncResult", {}).get("revision") == source_commit, "failed-run Application operation revision mismatch")
            require(application.get("status", {}).get("operationState", {}).get("phase") == "Succeeded", "failed-run Application operation did not succeed")
            require((application.get("spec", {}).get("syncPolicy", {}).get("automated", {}).get("selfHeal") or False) is False, "failed-run Application has self-heal enabled")
        if managed is not None:
            require(isinstance(managed, dict) and isinstance(managed.get("items"), list), "failed-run managed-resource response is invalid")
        if "scan-input.json" in files:
            require(application is not None and managed is not None, "failed-run scan input lacks component artifacts")
            scan_input = load(files["scan-input.json"])
            require(scan_input == {"application": application, "managedResources": managed}, "failed-run scan input mismatch")
            if "capturedInputSha256" in metadata:
                require(metadata["capturedInputSha256"] == sha256(files["scan-input.json"]), "failed-run scan-input hash mismatch")
        if "radar-result.json" in files:
            result = load(files["radar-result.json"])
            require(isinstance(result, dict), "failed-run RADAR result is invalid")
            require(result.get("application") == "radar-lab" and result.get("syncStatus") == "OutOfSync", "failed-run RADAR application mismatch")
            findings = result.get("findings")
            require(isinstance(findings, list), "failed-run RADAR findings are invalid")
        if metadata["baselineResetVerified"]:
            if "reset.json" not in files:
                require(failure_stage == "prepare-mutation", "verified failed-run reset lacks reset artifact")
            else:
                reset = load(files["reset.json"])
                require(isinstance(reset, dict), "failed-run reset is invalid")
                require(reset.get("declaredBaselineVerified") is True, "failed-run reset is not verified")
                require(reset.get("targetRevision") == source_commit and reset.get("operationRevision") == source_commit, "failed-run reset revision mismatch")
                require(reset.get("operationPhase") == "Succeeded", "failed-run reset operation did not succeed")
                require(reset.get("syncStatus") == "Synced" and reset.get("healthStatus") == "Healthy", "failed-run reset state mismatch")
                require(isinstance(reset.get("operationInitiator"), str) and reset["operationInitiator"].startswith("radar-reset-"), "failed-run reset initiator mismatch")
                reset_started = timestamp(reset.get("startedAt"), "reset.startedAt")
                reset_completed = timestamp(reset.get("completedAt"), "reset.completedAt")
                require((mutation_completed or started) <= reset_started <= reset_completed, "failed-run reset chronology mismatch")
        elif "reset.json" in files:
            reset = load(files["reset.json"])
            require(isinstance(reset, dict), "failed-run reset is invalid")
            require(reset.get("declaredBaselineVerified") is False, "unverified failed-run reset claims success")
            require(reset.get("targetRevision") in {None, source_commit}, "failed-run reset target mismatch")
            require(reset.get("operationRevision") in {None, source_commit}, "failed-run reset operation revision mismatch")
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
    matched_findings = [
        finding
        for finding in findings
        if isinstance(finding, dict)
        and finding.get("ruleId") == expected_rule
        and finding.get("severity") == expected_severity
        and finding.get("change", {}).get("path") == expected_path
    ]
    if schema_version == 3:
        require(bool(matched_findings), "expected decision and field path are absent")
    else:
        require(all(isinstance(finding, dict) for finding in findings), "formal result contains malformed findings")
        for finding in findings:
            require(isinstance(finding.get("resource"), dict), "formal finding lacks resource identity")
            require(isinstance(finding.get("change"), dict) and isinstance(finding["change"].get("operation"), str), "formal finding lacks atomic change")
            require(finding.get("severity") in {"INFO", "LOW", "MEDIUM", "HIGH", "CRITICAL"}, "formal finding has invalid severity")
            require(type(finding.get("score")) is int and 0 <= finding["score"] <= 100, "formal finding has invalid score")
            require(bool(finding.get("reason")) and bool(finding.get("recommendation")), "formal finding lacks explanation")
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
    parser.add_argument("--protocol-file", type=Path)
    parser.add_argument("run_dir", type=Path)
    args = parser.parse_args()
    try:
        protocol = args.protocol_file.resolve() if args.protocol_file else None
        validate_run(args.run_dir.resolve(), protocol)
    except EvidenceValidationError as error:
        print(f"evidence validation failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
