#!/usr/bin/env python3

import importlib.util
import json
import os
import tempfile
import unittest
from pathlib import Path

import yaml


SCRIPT = Path(__file__).with_name("sanitize-evidence.py")
SPEC = importlib.util.spec_from_file_location("sanitize_evidence", SCRIPT)
MODULE = importlib.util.module_from_spec(SPEC)
assert SPEC.loader
SPEC.loader.exec_module(MODULE)


class SanitizerTests(unittest.TestCase):
    def test_redacts_credentials_and_secret_data_but_keeps_reference(self):
        value = {
            "authorization": "Bearer abc.def.ghi",
            "resource": {"kind": "Secret", "data": {"token": "encoded"}},
            "secretKeyRef": {"name": "radar-demo-credentials-v2"},
        }
        result = MODULE.sanitize_value(value)
        self.assertEqual(result["authorization"], MODULE.REDACTED)
        self.assertEqual(result["resource"]["data"], MODULE.REDACTED)
        self.assertEqual(result["secretKeyRef"]["name"], "radar-demo-credentials-v2")

    def test_sanitizes_embedded_kubernetes_secret_json(self):
        embedded = json.dumps({"kind": "Secret", "stringData": {"demo-token": "value"}})
        result = MODULE.sanitize_value({"liveState": embedded})
        decoded = json.loads(result["liveState"])
        self.assertEqual(decoded["stringData"], MODULE.REDACTED)

    def test_sanitizes_yaml_credentials_and_secret(self):
        with tempfile.TemporaryDirectory() as root:
            source = Path(root) / "record.yaml"
            destination = Path(root) / "sanitized.yaml"
            source.write_text(
                "kind: Secret\nstringData:\n  password: unsafe\nclientSecret: exposed\n",
                encoding="utf-8",
            )
            MODULE.sanitize_file(source, destination)
            result = yaml.safe_load(destination.read_text(encoding="utf-8"))
            self.assertEqual(result["stringData"], MODULE.REDACTED)
            self.assertEqual(result["clientSecret"], MODULE.REDACTED)

    def test_sanitizes_kubeconfig_material(self):
        value = {
            "apiVersion": "v1",
            "clusters": [{"cluster": {"certificate-authority-data": "encoded"}}],
            "users": [
                {
                    "user": {
                        "client-certificate-data": "certificate",
                        "client-key-data": "private-key",
                        "token": "credential",
                    }
                }
            ],
        }
        result = MODULE.sanitize_value(value)
        self.assertEqual(result["clusters"][0]["cluster"]["certificate-authority-data"], MODULE.REDACTED)
        user = result["users"][0]["user"]
        self.assertEqual(user["client-certificate-data"], MODULE.REDACTED)
        self.assertEqual(user["client-key-data"], MODULE.REDACTED)
        self.assertEqual(user["token"], MODULE.REDACTED)

    def test_sanitizes_text_credentials(self):
        text = "password=unsafe\ntoken: abcdefghijkl\nAuthorization: Bearer abc.def.ghi\n"
        sanitized = MODULE.sanitize_text(text)
        self.assertNotIn("unsafe", sanitized)
        self.assertNotIn("abcdefghijkl", sanitized)
        self.assertNotIn("abc.def.ghi", sanitized)
        self.assertEqual(sanitized.count(MODULE.REDACTED), 3)

    def test_rejects_binary_file(self):
        with tempfile.TemporaryDirectory() as root:
            source = Path(root) / "record.txt"
            source.write_bytes(b"evidence\x00binary")
            with self.assertRaises(MODULE.UnsafeEvidenceError):
                MODULE.sanitize_file(source, Path(root) / "output.txt")

    def test_rejects_screenshot_and_unsupported_format(self):
        with tempfile.TemporaryDirectory() as root:
            screenshot = Path(root) / "screen.png"
            screenshot.write_bytes(b"not-a-real-image")
            with self.assertRaises(MODULE.UnsafeEvidenceError):
                MODULE.sanitize_file(screenshot, Path(root) / "output.png")
            unsupported = Path(root) / "capture.bin"
            unsupported.write_text("plain text", encoding="utf-8")
            with self.assertRaises(MODULE.UnsafeEvidenceError):
                MODULE.sanitize_file(unsupported, Path(root) / "output.bin")

    @unittest.skipUnless(hasattr(os, "symlink"), "symbolic links are unavailable")
    def test_rejects_symbolic_link(self):
        with tempfile.TemporaryDirectory() as root:
            source = Path(root) / "source"
            destination = Path(root) / "destination"
            source.mkdir()
            target = Path(root) / "outside.json"
            target.write_text("{}", encoding="utf-8")
            (source / "linked.json").symlink_to(target)
            with self.assertRaises(MODULE.UnsafeEvidenceError):
                MODULE.sanitize_directory(source, destination)
            self.assertFalse(destination.exists())

    def test_sanitizes_and_checks_directory_atomically(self):
        with tempfile.TemporaryDirectory() as root:
            source = Path(root) / "source"
            destination = Path(root) / "destination"
            source.mkdir()
            (source / "record.json").write_text(
                json.dumps({"password": "unsafe", "name": "guestbook"}), encoding="utf-8"
            )
            MODULE.sanitize_directory(source, destination)
            MODULE.assert_sanitized(destination)
            result = json.loads((destination / "record.json").read_text(encoding="utf-8"))
            self.assertEqual(result["password"], MODULE.REDACTED)
            self.assertEqual(result["name"], "guestbook")


if __name__ == "__main__":
    unittest.main()
