#!/usr/bin/env python3
"""Compare every declared baseline field with its live radar-lab resource."""

from __future__ import annotations

import argparse
import base64
import copy
import json
import subprocess
import sys
from pathlib import Path
from typing import Any

import yaml


class BaselineMismatch(ValueError):
    """Raised without echoing potentially sensitive field values."""


def prepare_expected(document: dict[str, Any]) -> dict[str, Any]:
    expected = copy.deepcopy(document)
    expected.pop("status", None)
    if expected.get("kind") == "Secret" and "stringData" in expected:
        encoded = {
            str(key): base64.b64encode(str(value).encode("utf-8")).decode("ascii")
            for key, value in expected.pop("stringData").items()
        }
        expected.setdefault("data", {}).update(encoded)
    return expected


def assert_declared_fields(expected: Any, actual: Any, path: str = "$") -> None:
    if isinstance(expected, dict):
        if not isinstance(actual, dict):
            raise BaselineMismatch(f"type differs at {path}")
        for key, expected_value in expected.items():
            child_path = f"{path}.{key}"
            if key not in actual:
                raise BaselineMismatch(f"declared field is missing at {child_path}")
            assert_declared_fields(expected_value, actual[key], child_path)
        return
    if isinstance(expected, list):
        if not isinstance(actual, list) or len(actual) != len(expected):
            raise BaselineMismatch(f"list differs at {path}")
        for index, expected_value in enumerate(expected):
            assert_declared_fields(expected_value, actual[index], f"{path}[{index}]")
        return
    if expected != actual:
        raise BaselineMismatch(f"declared value differs at {path}")


def resource_identity(document: dict[str, Any]) -> tuple[str, str, str]:
    kind = document.get("kind")
    metadata = document.get("metadata")
    if not isinstance(kind, str) or not isinstance(metadata, dict):
        raise BaselineMismatch("rendered document lacks kind or metadata")
    name = metadata.get("name")
    namespace = metadata.get("namespace", "")
    if not isinstance(name, str) or not name:
        raise BaselineMismatch("rendered document lacks metadata.name")
    if not isinstance(namespace, str):
        raise BaselineMismatch(f"invalid namespace for {kind}/{name}")
    return kind, namespace, name


def fetch_live(context: str, document: dict[str, Any]) -> dict[str, Any]:
    kind, namespace, name = resource_identity(document)
    command = ["kubectl", "--context", context]
    if namespace:
        command.extend(("--namespace", namespace))
    command.extend(("get", kind, name, "--output", "json"))
    try:
        result = subprocess.run(command, check=True, capture_output=True, text=True)
    except subprocess.CalledProcessError as error:
        raise BaselineMismatch(f"live resource is unavailable: {kind}/{namespace or '-'} /{name}") from error
    try:
        value = json.loads(result.stdout)
    except json.JSONDecodeError as error:
        raise BaselineMismatch(f"kubectl returned invalid JSON for {kind}/{name}") from error
    if not isinstance(value, dict):
        raise BaselineMismatch(f"kubectl returned an invalid object for {kind}/{name}")
    return value


def verify(context: str, rendered: Path) -> int:
    try:
        documents = [item for item in yaml.safe_load_all(rendered.read_text(encoding="utf-8")) if item]
    except (OSError, yaml.YAMLError) as error:
        print(f"baseline verification failed: rendered baseline is invalid: {error}", file=sys.stderr)
        return 1
    if not documents or any(not isinstance(item, dict) for item in documents):
        print("baseline verification failed: rendered baseline contains no valid resources", file=sys.stderr)
        return 1

    identities: set[tuple[str, str, str]] = set()
    try:
        for document in documents:
            identity = resource_identity(document)
            if identity in identities:
                raise BaselineMismatch(f"duplicate rendered resource: {identity[0]}/{identity[2]}")
            identities.add(identity)
            assert_declared_fields(prepare_expected(document), fetch_live(context, document))
    except BaselineMismatch as error:
        print(f"baseline verification failed: {error}", file=sys.stderr)
        return 1
    print(f"Verified {len(documents)} declared baseline resources.")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--context", required=True)
    parser.add_argument("--rendered", type=Path, required=True)
    args = parser.parse_args()
    if args.context != "radar-lab":
        parser.error("--context must be exactly radar-lab")
    return verify(args.context, args.rendered)


if __name__ == "__main__":
    raise SystemExit(main())
