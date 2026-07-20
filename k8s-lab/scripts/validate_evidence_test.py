#!/usr/bin/env python3

import copy
import hashlib
import importlib.util
import json
import os
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).with_name("validate-evidence.py")
SPEC = importlib.util.spec_from_file_location("validate_evidence", SCRIPT)
MODULE = importlib.util.module_from_spec(SPEC)
assert SPEC.loader
SPEC.loader.exec_module(MODULE)
SANITIZER_SCRIPT = Path(__file__).with_name("sanitize-evidence.py")
SANITIZER_SPEC = importlib.util.spec_from_file_location("sanitize_evidence_for_validation", SANITIZER_SCRIPT)
SANITIZER = importlib.util.module_from_spec(SANITIZER_SPEC)
assert SANITIZER_SPEC.loader
SANITIZER_SPEC.loader.exec_module(SANITIZER)
GENERATOR_SCRIPT = Path(__file__).with_name("generate-formal-protocol.py")
GENERATOR_SPEC = importlib.util.spec_from_file_location("generate_protocol_for_validation", GENERATOR_SCRIPT)
GENERATOR = importlib.util.module_from_spec(GENERATOR_SPEC)
assert GENERATOR_SPEC.loader
GENERATOR_SPEC.loader.exec_module(GENERATOR)


COMMIT = "0123456789abcdef0123456789abcdef01234567"


def write_json(root: Path, name: str, value) -> None:
    (root / name).write_text(json.dumps(value, indent=2) + "\n", encoding="utf-8")


def create_valid_run(root: Path) -> None:
    environment = {
        "collectionId": "runner-integrity-v1",
        "capturedAt": "2026-07-20T09:59:00Z",
        "source": {"commit": COMMIT},
        "provider": "GitHub Codespaces",
    }
    write_json(root, "environment.json", environment)
    environment_hash = hashlib.sha256((root / "environment.json").read_bytes()).hexdigest()
    application = {
        "metadata": {"name": "radar-lab", "uid": "uid", "resourceVersion": "42"},
        "spec": {
            "project": "radar",
            "source": {"targetRevision": COMMIT},
            "syncPolicy": {"automated": {"selfHeal": False}},
        },
        "status": {
            "sync": {"revision": COMMIT, "status": "OutOfSync"},
            "health": {"status": "Progressing"},
            "operationState": {"phase": "Succeeded", "syncResult": {"revision": COMMIT}},
        },
    }
    managed = {"items": []}
    scan_input = {"application": application, "managedResources": managed}
    write_json(root, "argocd-application.json", application)
    write_json(root, "argocd-managed-resources.json", managed)
    write_json(root, "scan-input.json", scan_input)
    scan_hash = hashlib.sha256((root / "scan-input.json").read_bytes()).hexdigest()
    write_json(
        root,
        "metadata.json",
        {
            "evidenceSchemaVersion": 3,
            "collectionId": "runner-integrity-v1",
            "scenario": "privileged-container",
            "repetition": 1,
            "startedAt": "2026-07-20T10:00:00Z",
            "sourceCommit": COMMIT,
            "scannerSha256": "1" * 64,
            "policySha256": "2" * 64,
            "environmentSha256": environment_hash,
            "capturedInputSha256": scan_hash,
            "applicationResourceVersion": "42",
            "captureAttempt": 1,
            "argoTargetRevision": COMMIT,
            "argoSynchronizedRevision": COMMIT,
            "argoOperationRevision": COMMIT,
            "argoOperationPhase": "Succeeded",
            "expectedRule": "RADAR-WORKLOAD-PRIVILEGED",
            "expectedSeverity": "CRITICAL",
            "mutationAt": "2026-07-20T10:00:01Z",
            "observedAt": "2026-07-20T10:00:02Z",
            "radarCompletedAt": "2026-07-20T10:00:03Z",
            "completedAt": "2026-07-20T10:00:05Z",
            "status": "completed",
            "baselineResetVerified": True,
            "evidenceTier": "controlled-lab-observed",
        },
    )
    write_json(
        root,
        "mutation.json",
        {
            "collectionId": "runner-integrity-v1",
            "scenario": "privileged-container",
            "startedAt": "2026-07-20T10:00:01Z",
            "completedAt": "2026-07-20T10:00:01Z",
        },
    )
    write_json(
        root,
        "argocd-observation.json",
        {
            "application": "radar-lab",
            "project": "radar",
            "targetRevision": COMMIT,
            "synchronizedRevision": COMMIT,
            "operationRevision": COMMIT,
            "operationPhase": "Succeeded",
            "applicationResourceVersion": "42",
            "syncStatus": "OutOfSync",
            "healthStatus": "Progressing",
            "observedAt": "2026-07-20T10:00:02Z",
        },
    )
    write_json(
        root,
        "radar-result.json",
        {
            "application": "radar-lab",
            "syncStatus": "OutOfSync",
            "findings": [
                {
                    "ruleId": "RADAR-WORKLOAD-PRIVILEGED",
                    "severity": "CRITICAL",
                    "change": {
                        "path": "/spec/template/spec/containers/0/securityContext/privileged"
                    },
                }
            ],
        },
    )
    write_json(
        root,
        "reset.json",
        {
            "startedAt": "2026-07-20T10:00:04Z",
            "completedAt": "2026-07-20T10:00:05Z",
            "targetRevision": COMMIT,
            "operationRevision": COMMIT,
            "operationPhase": "Succeeded",
            "operationInitiator": "radar-reset-1",
            "syncStatus": "Synced",
            "healthStatus": "Healthy",
            "declaredBaselineVerified": True,
        },
    )


class EvidenceValidatorTests(unittest.TestCase):
    def with_run(self):
        temporary = tempfile.TemporaryDirectory()
        root = Path(temporary.name)
        create_valid_run(root)
        return temporary, root

    def test_accepts_valid_completed_chain(self):
        temporary, root = self.with_run()
        with temporary:
            MODULE.validate_run(root)

    def test_accepts_chain_after_sanitization(self):
        temporary, root = self.with_run()
        with temporary, tempfile.TemporaryDirectory() as output_root:
            destination = Path(output_root) / "sanitized"
            SANITIZER.sanitize_directory(root, destination)
            MODULE.validate_run(destination)

    def test_rejects_unknown_status_and_empty_artifact(self):
        temporary, root = self.with_run()
        with temporary:
            metadata = json.loads((root / "metadata.json").read_text(encoding="utf-8"))
            metadata["status"] = "completedd"
            write_json(root, "metadata.json", metadata)
            with self.assertRaises(MODULE.EvidenceValidationError):
                MODULE.validate_run(root)
            (root / "metadata.json").write_text("{}\n", encoding="utf-8")
            with self.assertRaises(MODULE.EvidenceValidationError):
                MODULE.validate_run(root)

    def test_rejects_commit_scan_result_reset_and_time_mismatches(self):
        mutations = (
            ("environment.json", lambda value: value["source"].update(commit="f" * 40)),
            ("scan-input.json", lambda value: value.update(managedResources=[{}])),
            ("radar-result.json", lambda value: value["findings"][0].update(severity="LOW")),
            ("reset.json", lambda value: value.update(operationRevision="f" * 40)),
            ("reset.json", lambda value: value.update(startedAt="2026-07-20T09:00:00Z")),
        )
        for filename, mutate in mutations:
            with self.subTest(filename=filename):
                temporary, root = self.with_run()
                with temporary:
                    value = json.loads((root / filename).read_text(encoding="utf-8"))
                    mutate(value)
                    write_json(root, filename, value)
                    with self.assertRaises(MODULE.EvidenceValidationError):
                        MODULE.validate_run(root)

    def test_rejects_duplicate_keys_unexpected_files_and_hard_links(self):
        temporary, root = self.with_run()
        with temporary:
            (root / "metadata.json").write_text('{"status":"failed","status":"completed"}', encoding="utf-8")
            with self.assertRaises(MODULE.EvidenceValidationError):
                MODULE.validate_run(root)
        temporary, root = self.with_run()
        with temporary:
            (root / "unexpected.json").write_text("{}", encoding="utf-8")
            with self.assertRaises(MODULE.EvidenceValidationError):
                MODULE.validate_run(root)
        temporary, root = self.with_run()
        with temporary:
            os.link(root / "environment.json", root / "environment-copy.json")
            with self.assertRaises(MODULE.EvidenceValidationError):
                MODULE.validate_run(root)

    def test_failed_run_validates_present_reset_and_artifacts(self):
        temporary, root = self.with_run()
        with temporary:
            metadata = json.loads((root / "metadata.json").read_text(encoding="utf-8"))
            metadata.update(
                status="failed",
                evidenceTier="implemented",
                failedAt="2026-07-20T10:00:03Z",
                failureStage="reset-baseline",
                exitCode=1,
                baselineResetVerified=True,
            )
            write_json(root, "metadata.json", metadata)
            MODULE.validate_run(root)
        mutations = (
            ("argocd-observation.json", lambda value: value.update(targetRevision="f" * 40)),
            ("argocd-observation.json", lambda value: value.update(observedAt="2026-07-20T09:00:00Z")),
            ("argocd-application.json", lambda value: value["status"]["operationState"]["syncResult"].update(revision="f" * 40)),
            ("scan-input.json", lambda value: value.update(managedResources={"items": [{}]})),
            ("radar-result.json", lambda value: value.update(application="other-lab")),
            ("reset.json", lambda value: value.update(operationRevision="f" * 40)),
            ("reset.json", lambda value: value.update(startedAt="2026-07-20T09:00:00Z")),
        )
        for filename, mutate in mutations:
            with self.subTest(filename=filename):
                temporary, root = self.with_run()
                with temporary:
                    metadata = json.loads((root / "metadata.json").read_text(encoding="utf-8"))
                    metadata.update(
                        status="failed",
                        evidenceTier="implemented",
                        failedAt="2026-07-20T10:00:03Z",
                        failureStage="reset-baseline",
                        exitCode=1,
                        baselineResetVerified=True,
                    )
                    write_json(root, "metadata.json", metadata)
                    value = json.loads((root / filename).read_text(encoding="utf-8"))
                    mutate(value)
                    write_json(root, filename, value)
                    with self.assertRaises(MODULE.EvidenceValidationError):
                        MODULE.validate_run(root)

    def test_failed_run_requires_stage_complete_artifacts_and_nonzero_exit(self):
        temporary, root = self.with_run()
        with temporary:
            metadata = json.loads((root / "metadata.json").read_text(encoding="utf-8"))
            metadata.update(
                status="failed",
                evidenceTier="implemented",
                failedAt="2026-07-20T10:00:03Z",
                failureStage="reset-baseline",
                exitCode=1,
                baselineResetVerified=True,
            )
            write_json(root, "metadata.json", metadata)
            (root / "mutation.json").unlink()
            with self.assertRaises(MODULE.EvidenceValidationError):
                MODULE.validate_run(root)
            metadata["failureStage"] = "unknown-stage"
            write_json(root, "metadata.json", metadata)
            with self.assertRaises(MODULE.EvidenceValidationError):
                MODULE.validate_run(root)
            metadata["failureStage"] = "reset-baseline"
            metadata["exitCode"] = 0
            write_json(root, "metadata.json", metadata)
            with self.assertRaises(MODULE.EvidenceValidationError):
                MODULE.validate_run(root)

    def test_failed_run_before_mutation_preserves_minimal_evidence(self):
        temporary, root = self.with_run()
        with temporary:
            for artifact in MODULE.ALLOWED_FILES - {"metadata.json", "environment.json"}:
                (root / artifact).unlink()
            metadata = json.loads((root / "metadata.json").read_text(encoding="utf-8"))
            metadata.update(
                status="failed",
                evidenceTier="implemented",
                failedAt="2026-07-20T10:00:01Z",
                failureStage="prepare-mutation",
                exitCode=1,
                baselineResetVerified=True,
            )
            write_json(root, "metadata.json", metadata)
            MODULE.validate_run(root)

    def test_schema_v4_binds_protocol_and_formal_ground_truth(self):
        temporary, root = self.with_run()
        with temporary, tempfile.TemporaryDirectory() as protocol_root:
            protocol_path = Path(protocol_root) / "formal-evaluation-v1.json"
            protocol = GENERATOR.build_protocol()
            protocol_path.write_text(json.dumps(protocol, indent=2) + "\n", encoding="utf-8")
            environment = json.loads((root / "environment.json").read_text(encoding="utf-8"))
            environment["collectionId"] = "formal-evaluation-v1"
            write_json(root, "environment.json", environment)
            metadata = json.loads((root / "metadata.json").read_text(encoding="utf-8"))
            declaration = next(
                run
                for run in protocol["runs"]
                if run["scenario"] == "privileged-container" and run["repetition"] == 1
            )
            metadata.update(
                evidenceSchemaVersion=4,
                collectionId="formal-evaluation-v1",
                evidenceTier="formally-evaluated",
                environmentSha256=hashlib.sha256((root / "environment.json").read_bytes()).hexdigest(),
                protocolId="formal-evaluation-v1",
                protocolSha256=hashlib.sha256(protocol_path.read_bytes()).hexdigest(),
                declaredRunId=declaration["runId"],
                groundTruth=declaration["groundTruth"],
                expectedScore=declaration["expectedScore"],
                expectedPath=declaration["expectedPath"],
                riskMatrixSha256="3" * 64,
            )
            write_json(root, "metadata.json", metadata)
            mutation = json.loads((root / "mutation.json").read_text(encoding="utf-8"))
            mutation["collectionId"] = "formal-evaluation-v1"
            write_json(root, "mutation.json", mutation)
            result = json.loads((root / "radar-result.json").read_text(encoding="utf-8"))
            result["findings"][0].update(
                score=declaration["expectedScore"],
                resource={"kind": "Deployment", "name": "radar-demo"},
                reason="Declared formal decision",
                recommendation="Restore the declared baseline",
            )
            result["findings"][0]["change"]["operation"] = "replace"
            write_json(root, "radar-result.json", result)
            MODULE.validate_run(root, protocol_path)
            result["findings"] = []
            write_json(root, "radar-result.json", result)
            MODULE.validate_run(root, protocol_path)
            metadata["protocolSha256"] = "4" * 64
            write_json(root, "metadata.json", metadata)
            with self.assertRaises(MODULE.EvidenceValidationError):
                MODULE.validate_run(root, protocol_path)


if __name__ == "__main__":
    unittest.main()
