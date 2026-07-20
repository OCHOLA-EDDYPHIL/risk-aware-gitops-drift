#!/usr/bin/env python3

import importlib.util
import json
import os
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).with_name("sanitize-evidence.py")
SPEC = importlib.util.spec_from_file_location("sanitize_evidence", SCRIPT)
MODULE = importlib.util.module_from_spec(SPEC)
assert SPEC.loader
SPEC.loader.exec_module(MODULE)


class SanitizerTests(unittest.TestCase):
    def test_redacts_api_keys_secret_data_and_kubeconfig_exec_env(self):
        value = {
            "apiKey": "unsafe",
            "resource": {"kind": "Secret", "data": {"token": "encoded"}},
            "exec": {"env": [{"name": "TOKEN", "value": "credential"}]},
            "secretKeyRef": {"name": "radar-demo-credentials-v2"},
        }
        result = MODULE.sanitize_value(value)
        self.assertEqual(result["apiKey"], MODULE.REDACTED)
        self.assertEqual(result["resource"]["data"], MODULE.REDACTED)
        self.assertEqual(result["exec"]["env"][0]["value"], MODULE.REDACTED)
        self.assertEqual(result["secretKeyRef"]["name"], "radar-demo-credentials-v2")

    def test_sanitizes_embedded_kubernetes_secret_json(self):
        embedded = json.dumps({"kind": "Secret", "stringData": {"demo-token": "value"}})
        result = MODULE.sanitize_value({"liveState": embedded})
        decoded = json.loads(result["liveState"])
        self.assertEqual(decoded["stringData"], MODULE.REDACTED)

    def test_rejects_embedded_yaml_secret_and_control_characters(self):
        with self.assertRaises(MODULE.UnsafeEvidenceError):
            MODULE.sanitize_value({"liveState": "apiVersion: v1\nkind: Secret\ndata:\n  token: abc\n"})
        with self.assertRaises(MODULE.UnsafeEvidenceError):
            MODULE.sanitize_text("evidence\x01payload")

    def test_rejects_duplicate_json_keys(self):
        with self.assertRaises(MODULE.UnsafeEvidenceError):
            MODULE.load_json('{"token":"one","token":"two"}')
        with self.assertRaises(MODULE.UnsafeEvidenceError):
            MODULE.sanitize_value(
                {"liveState": '{"kind":"Secret","data":{"token":"one"},"data":{"token":"two"}}'}
            )
        with self.assertRaises(MODULE.UnsafeEvidenceError):
            MODULE.sanitize_value({"liveState": "[1,]"})

    def test_rejects_unexpected_binary_and_hard_linked_artifacts(self):
        with tempfile.TemporaryDirectory() as root:
            root_path = Path(root)
            unexpected = root_path / "record.json"
            unexpected.write_text("{}", encoding="utf-8")
            with self.assertRaises(MODULE.UnsafeEvidenceError):
                MODULE.sanitize_file(unexpected, root_path / "output.json")
            binary = root_path / "metadata.json"
            binary.write_bytes(b"evidence\x00binary")
            with self.assertRaises(MODULE.UnsafeEvidenceError):
                MODULE.sanitize_file(binary, root_path / "output.json")
            binary.write_text("{}", encoding="utf-8")
            hard_link = root_path / "environment.json"
            os.link(binary, hard_link)
            with self.assertRaises(MODULE.UnsafeEvidenceError):
                MODULE.sanitize_file(hard_link, root_path / "output.json")

    @unittest.skipUnless(hasattr(os, "symlink"), "symbolic links are unavailable")
    def test_rejects_symbolic_link_and_nested_directory(self):
        with tempfile.TemporaryDirectory() as root:
            root_path = Path(root)
            source = root_path / "source"
            source.mkdir()
            target = root_path / "outside.json"
            target.write_text("{}", encoding="utf-8")
            (source / "metadata.json").symlink_to(target)
            with self.assertRaises(MODULE.UnsafeEvidenceError):
                MODULE.sanitize_directory(source, root_path / "destination")
            (source / "metadata.json").unlink()
            (source / "metadata.json").write_text("{}", encoding="utf-8")
            (source / "nested").mkdir()
            with self.assertRaises(MODULE.UnsafeEvidenceError):
                MODULE.sanitize_directory(source, root_path / "destination")

    def test_sanitizes_known_directory_atomically_and_updates_hashes(self):
        with tempfile.TemporaryDirectory() as root:
            root_path = Path(root)
            source = root_path / "source"
            destination = root_path / "destination"
            source.mkdir()
            (source / "metadata.json").write_text(
                json.dumps({"environmentSha256": "0" * 64, "password": "unsafe"}),
                encoding="utf-8",
            )
            (source / "environment.json").write_text(
                json.dumps({"provider": "GitHub Codespaces"}), encoding="utf-8"
            )
            MODULE.sanitize_directory(source, destination)
            MODULE.assert_sanitized(destination)
            metadata = json.loads((destination / "metadata.json").read_text(encoding="utf-8"))
            self.assertEqual(metadata["password"], MODULE.REDACTED)
            self.assertRegex(metadata["environmentSha256"], r"^[0-9a-f]{64}$")


if __name__ == "__main__":
    unittest.main()
