#!/usr/bin/env python3

import importlib.util
import json
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).with_name("summarize-evaluation.py")
SPEC = importlib.util.spec_from_file_location("summarize_evaluation", SCRIPT)
MODULE = importlib.util.module_from_spec(SPEC)
assert SPEC.loader
SPEC.loader.exec_module(MODULE)
GENERATOR_SCRIPT = Path(__file__).with_name("generate-formal-protocol.py")
GENERATOR_SPEC = importlib.util.spec_from_file_location("generate_protocol_for_metrics", GENERATOR_SCRIPT)
GENERATOR = importlib.util.module_from_spec(GENERATOR_SPEC)
assert GENERATOR_SPEC.loader
GENERATOR_SPEC.loader.exec_module(GENERATOR)


def write_json(path: Path, value) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value), encoding="utf-8")


class MetricsTests(unittest.TestCase):
    def test_nearest_rank(self):
        self.assertEqual(MODULE.nearest_rank([1, 2, 3, 4, 5], 0.95), 5)
        self.assertIsNone(MODULE.nearest_rank([], 0.95))

    def test_derives_declared_denominators_and_preserves_missing_runs(self):
        protocol = GENERATOR.build_protocol()
        with tempfile.TemporaryDirectory() as root:
            collection = Path(root)
            first = protocol["runs"][0]
            summary = collection / "runs" / first["scenario"] / "run-001"
            write_json(
                summary / "metadata.json",
                {
                    "declaredRunId": first["runId"],
                    "evidenceSchemaVersion": 4,
                    "evidenceTier": "formally-evaluated",
                    "protocolId": "formal-evaluation-v1",
                    "protocolSha256": "a" * 64,
                    "sourceCommit": "b" * 40,
                    "scannerSha256": "c" * 64,
                    "policySha256": "d" * 64,
                    "riskMatrixSha256": "e" * 64,
                    "environmentSha256": "f" * 64,
                    "status": "completed",
                    "baselineResetVerified": True,
                    "mutationAt": "2026-07-20T10:00:00Z",
                    "observedAt": "2026-07-20T10:00:02Z",
                    "radarCompletedAt": "2026-07-20T10:00:05Z",
                },
            )
            write_json(
                summary / "radar-result.json",
                {
                    "findings": [
                        {
                            "ruleId": first["expectedRule"],
                            "severity": first["expectedSeverity"],
                            "resource": {"kind": "Role", "name": "radar-demo-reader"},
                            "change": {"operation": "replace", "path": first["expectedPath"]},
                            "reason": "declared reason",
                            "recommendation": "declared recommendation",
                        }
                    ]
                },
            )
            rows, metrics = MODULE.derive(protocol, collection)
            self.assertEqual(len(rows), 80)
            self.assertEqual(metrics["declaredRuns"], 80)
            self.assertEqual(metrics["detectedSecurityRuns"], 1)
            self.assertEqual(metrics["falseNegatives"], 69)
            self.assertEqual(metrics["timeToDetectSeconds"]["median"], 5)
            self.assertEqual(metrics["processingLatencySeconds"]["median"], 3)


if __name__ == "__main__":
    unittest.main()
