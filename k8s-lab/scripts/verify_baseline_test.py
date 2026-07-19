#!/usr/bin/env python3

import base64
import importlib.util
import unittest
from pathlib import Path


SCRIPT = Path(__file__).with_name("verify-baseline.py")
SPEC = importlib.util.spec_from_file_location("verify_baseline", SCRIPT)
MODULE = importlib.util.module_from_spec(SPEC)
assert SPEC.loader
SPEC.loader.exec_module(MODULE)


class BaselineVerifierTests(unittest.TestCase):
    def test_allows_undeclared_server_fields(self):
        expected = {"metadata": {"name": "demo", "labels": {"app": "demo"}}, "spec": {"replicas": 1}}
        actual = {
            "metadata": {
                "name": "demo",
                "labels": {"app": "demo"},
                "annotations": {"argocd.argoproj.io/tracking-id": "synthetic"},
                "generation": 2,
            },
            "spec": {"replicas": 1, "revisionHistoryLimit": 10},
            "status": {"availableReplicas": 1},
        }
        MODULE.assert_declared_fields(expected, actual)

    def test_rejects_changed_declared_field_without_echoing_value(self):
        with self.assertRaisesRegex(MODULE.BaselineMismatch, r"declared value differs at \$\.spec\.replicas") as raised:
            MODULE.assert_declared_fields({"spec": {"replicas": 1}}, {"spec": {"replicas": 2}})
        self.assertNotIn("2", str(raised.exception))

    def test_normalizes_secret_string_data(self):
        expected = MODULE.prepare_expected(
            {"kind": "Secret", "metadata": {"name": "demo"}, "stringData": {"token": "dummy"}}
        )
        self.assertNotIn("stringData", expected)
        self.assertEqual(expected["data"]["token"], base64.b64encode(b"dummy").decode("ascii"))

    def test_requires_equal_declared_list(self):
        with self.assertRaises(MODULE.BaselineMismatch):
            MODULE.assert_declared_fields({"rules": ["get"]}, {"rules": ["get", "list"]})

    def test_allows_api_omission_of_declared_empty_collection(self):
        MODULE.assert_declared_fields(
            {"spec": {"ingress": [], "policyTypes": ["Ingress"]}},
            {"spec": {"policyTypes": ["Ingress"]}},
        )


if __name__ == "__main__":
    unittest.main()
