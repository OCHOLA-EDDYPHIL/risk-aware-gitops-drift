#!/usr/bin/env python3

import importlib.util
import json
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).with_name("run-collection.py")
SPEC = importlib.util.spec_from_file_location("run_collection", SCRIPT)
MODULE = importlib.util.module_from_spec(SPEC)
assert SPEC.loader
SPEC.loader.exec_module(MODULE)

GENERATOR_SCRIPT = Path(__file__).with_name("generate-formal-protocol.py")
GENERATOR_SPEC = importlib.util.spec_from_file_location("generate_protocol", GENERATOR_SCRIPT)
GENERATOR = importlib.util.module_from_spec(GENERATOR_SPEC)
assert GENERATOR_SPEC.loader
GENERATOR_SPEC.loader.exec_module(GENERATOR)


class RunCollectionTests(unittest.TestCase):
    def test_generated_protocol_declares_unique_eighty_run_matrix(self):
        protocol = GENERATOR.build_protocol()
        runs = MODULE.validate_protocol(protocol)
        self.assertEqual(len(runs), 80)
        self.assertEqual(len({run["runId"] for run in runs}), 80)
        self.assertEqual(len({(run["scenario"], run["repetition"]) for run in runs}), 80)

    def test_rejects_duplicate_and_incomplete_protocols(self):
        protocol = GENERATOR.build_protocol()
        protocol["runs"][1]["runId"] = protocol["runs"][0]["runId"]
        with self.assertRaises(MODULE.CollectionError):
            MODULE.validate_protocol(protocol)
        protocol = GENERATOR.build_protocol()
        protocol["runs"].pop()
        with self.assertRaises(MODULE.CollectionError):
            MODULE.validate_protocol(protocol)

    def test_existing_run_requires_matching_identity_and_verified_reset(self):
        with tempfile.TemporaryDirectory() as root:
            run_dir = Path(root)
            metadata = {
                "declaredRunId": "formal-evaluation-v1-rbac-wildcard-r01",
                "status": "failed",
                "baselineResetVerified": True,
                "environmentSha256": "a" * 64,
            }
            (run_dir / "metadata.json").write_text(json.dumps(metadata), encoding="utf-8")
            self.assertTrue(
                MODULE.completed_or_safe_failure(run_dir, metadata["declaredRunId"], "a" * 64)
            )
            with self.assertRaises(MODULE.CollectionError):
                MODULE.completed_or_safe_failure(run_dir, metadata["declaredRunId"], "b" * 64)
            metadata["baselineResetVerified"] = False
            (run_dir / "metadata.json").write_text(json.dumps(metadata), encoding="utf-8")
            with self.assertRaises(MODULE.CollectionError):
                MODULE.completed_or_safe_failure(run_dir, metadata["declaredRunId"])


if __name__ == "__main__":
    unittest.main()
