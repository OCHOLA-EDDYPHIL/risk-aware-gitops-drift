#!/usr/bin/env python3
"""Execute each declared RADAR protocol run exactly once, preserving failures."""

from __future__ import annotations

import argparse
import hashlib
import json
import subprocess
import sys
from pathlib import Path
from typing import Any


class CollectionError(ValueError):
    pass


def reject_duplicates(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise CollectionError(f"duplicate JSON key: {key}")
        result[key] = value
    return result


def load_json(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"), object_pairs_hook=reject_duplicates)
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as error:
        raise CollectionError(f"invalid JSON: {path}") from error
    if not isinstance(value, dict):
        raise CollectionError(f"JSON object required: {path}")
    return value


def validate_protocol(protocol: dict[str, Any]) -> list[dict[str, Any]]:
    if protocol.get("protocolVersion") != 1 or protocol.get("evidenceSchemaVersion") != 4:
        raise CollectionError("formal protocol version or evidence schema is unsupported")
    if protocol.get("protocolId") != protocol.get("collectionId"):
        raise CollectionError("protocol and collection identifiers must match")
    runs = protocol.get("runs")
    if not isinstance(runs, list) or len(runs) != protocol.get("declaredRunCount") or len(runs) != 80:
        raise CollectionError("formal protocol must declare exactly 80 runs")
    identifiers: set[str] = set()
    pairs: set[tuple[str, int]] = set()
    for run in runs:
        if not isinstance(run, dict) or not isinstance(run.get("runId"), str):
            raise CollectionError("protocol run is malformed")
        repetition = run.get("repetition")
        pair = (run.get("scenario"), repetition)
        if run["runId"] in identifiers or pair in pairs:
            raise CollectionError("protocol contains duplicate run identity")
        if type(repetition) is not int or not 1 <= repetition <= 10:
            raise CollectionError("protocol repetition is invalid")
        identifiers.add(run["runId"])
        pairs.add(pair)
    return runs


def completed_or_safe_failure(
    run_dir: Path, expected_run_id: str, expected_environment_sha256: str | None = None
) -> bool:
    metadata_path = run_dir / "metadata.json"
    if not metadata_path.is_file() or metadata_path.is_symlink():
        return False
    metadata = load_json(metadata_path)
    if metadata.get("declaredRunId") != expected_run_id:
        raise CollectionError(f"existing evidence has the wrong run identity: {run_dir}")
    if expected_environment_sha256 is not None and metadata.get("environmentSha256") != expected_environment_sha256:
        raise CollectionError(f"existing evidence belongs to a different environment: {run_dir}")
    if metadata.get("status") not in {"completed", "failed"}:
        raise CollectionError(f"existing evidence is not terminal: {run_dir}")
    if metadata.get("baselineResetVerified") is not True:
        raise CollectionError(f"existing run lacks a verified baseline reset: {run_dir}")
    return True


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--context", required=True)
    parser.add_argument("--protocol-file", required=True, type=Path)
    parser.add_argument("--environment-file", required=True, type=Path)
    parser.add_argument("--output-dir", required=True, type=Path)
    args = parser.parse_args()
    if args.context != "radar-lab":
        parser.error("--context must be radar-lab")

    protocol_path = args.protocol_file.resolve()
    environment_path = args.environment_file.resolve()
    output_root = args.output_dir.resolve()
    protocol = load_json(protocol_path)
    runs = validate_protocol(protocol)
    collection_id = protocol["collectionId"]
    environment = load_json(environment_path)
    if environment.get("collectionId") != collection_id:
        raise CollectionError("environment and protocol collection identifiers differ")
    environment_sha256 = hashlib.sha256(environment_path.read_bytes()).hexdigest()
    sidecar = Path(str(environment_path) + ".sha256")
    if not sidecar.is_file() or sidecar.is_symlink():
        raise CollectionError("environment checksum sidecar is missing or unsafe")
    sidecar_fields = sidecar.read_text(encoding="utf-8").split()
    if not sidecar_fields or sidecar_fields[0] != environment_sha256:
        raise CollectionError("environment checksum sidecar does not match")
    runner = Path(__file__).with_name("run-scenario.sh")
    validator = Path(__file__).with_name("validate-evidence.py")

    for position, run in enumerate(runs, start=1):
        scenario = run["scenario"]
        repetition = run["repetition"]
        run_dir = output_root / scenario / f"run-{repetition:03d}"
        if run_dir.exists():
            if completed_or_safe_failure(run_dir, run["runId"], environment_sha256):
                subprocess.run(
                    [sys.executable, str(validator), "--protocol-file", str(protocol_path), str(run_dir)],
                    check=True,
                )
                print(f"[{position}/80] preserving existing {run['runId']}")
                continue
            raise CollectionError(f"unsafe partial run exists: {run_dir}")

        print(f"[{position}/80] executing {run['runId']}", flush=True)
        result = subprocess.run(
            [
                str(runner),
                "--context",
                args.context,
                "--collection-id",
                collection_id,
                "--scenario",
                scenario,
                "--repetition",
                str(repetition),
                "--environment-file",
                str(environment_path),
                "--protocol-file",
                str(protocol_path),
                "--output-dir",
                str(output_root),
            ],
            check=False,
        )
        if not run_dir.is_dir():
            raise CollectionError(f"runner produced no evidence directory for {run['runId']}")
        subprocess.run(
            [sys.executable, str(validator), "--protocol-file", str(protocol_path), str(run_dir)],
            check=True,
        )
        metadata = load_json(run_dir / "metadata.json")
        if metadata.get("baselineResetVerified") is not True:
            raise CollectionError(f"baseline reset is unverified after {run['runId']}")
        if result.returncode != 0:
            print(f"[{position}/80] preserved failed run {run['runId']}", file=sys.stderr)

    print("All 80 declared protocol runs are present with verified terminal evidence.")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except CollectionError as error:
        print(f"collection execution failed: {error}", file=sys.stderr)
        raise SystemExit(1)
