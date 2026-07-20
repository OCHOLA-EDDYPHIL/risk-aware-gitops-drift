#!/usr/bin/env python3
"""Create a fail-closed sanitized copy of one RADAR run directory."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import shutil
import tempfile
from pathlib import Path
from typing import Any


REDACTED = "<redacted>"
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
SENSITIVE_KEYS = {
    "accesstoken",
    "apikey",
    "apikeyvalue",
    "authorization",
    "awsaccesskeyid",
    "awssecretaccesskey",
    "certificateauthoritydata",
    "clientcertificate",
    "clientcertificatedata",
    "clientkey",
    "clientkeydata",
    "clientsecret",
    "credential",
    "credentials",
    "idtoken",
    "password",
    "privatekey",
    "refreshtoken",
    "secretaccesskey",
    "secretvalue",
    "sessiontoken",
    "sshprivatekey",
    "token",
}
PRIVATE_KEY_PATTERN = re.compile(r"-----BEGIN (?:OPENSSH|RSA|EC|DSA)? ?PRIVATE KEY-----")
EMBEDDED_YAML_SECRET_PATTERN = re.compile(
    r"(?ims)(?:^|\n)\s*kind\s*:\s*Secret\s*(?:\n|$).*?(?:^|\n)\s*(?:data|stringData)\s*:"
)
CONTROL_CHARACTER_PATTERN = re.compile(r"[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]")
AUTHORIZATION_PATTERN = re.compile(
    r"(?i)(authorization\s*[:=]\s*)(?:bearer\s+)?[A-Za-z0-9._~+/=-]{8,}"
)
BEARER_PATTERN = re.compile(r"(?i)(bearer\s+)[A-Za-z0-9._~+/=-]{8,}")
GITHUB_TOKEN_PATTERN = re.compile(r"\b(?:ghp|github_pat)_[A-Za-z0-9_]{20,}\b")
TEXT_CREDENTIAL_PATTERN = re.compile(
    r"(?im)^(\s*(?:access[-_ ]?token|api[-_ ]?key|authorization|client[-_ ]?secret|"
    r"client[-_ ]?key[-_ ]?data|client[-_ ]?certificate[-_ ]?data|password|"
    r"private[-_ ]?key|refresh[-_ ]?token|secret[-_ ]?access[-_ ]?key|token)"
    r"\s*[:=]\s*)(?!<redacted>\s*$)(?:\"[^\"\r\n]*\"|'[^'\r\n]*'|[^\s#]+)"
)


class UnsafeEvidenceError(ValueError):
    pass


def normalized_key(value: str) -> str:
    return re.sub(r"[^a-z0-9]", "", value.lower())


def reject_duplicate_keys(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise UnsafeEvidenceError(f"duplicate JSON key rejected: {key}")
        result[key] = value
    return result


def load_json(text: str) -> Any:
    try:
        return json.loads(text, object_pairs_hook=reject_duplicate_keys)
    except json.JSONDecodeError as error:
        raise UnsafeEvidenceError("invalid JSON rejected") from error


def sanitize_value(value: Any, parent_kind: str = "", path: tuple[str, ...] = ()) -> Any:
    if isinstance(value, dict):
        declared_kind = value.get("kind", parent_kind)
        kind = declared_kind if isinstance(declared_kind, str) else parent_kind
        named_credential = normalized_key(str(value.get("name", ""))) in SENSITIVE_KEYS
        sanitized: dict[Any, Any] = {}
        for key, child in value.items():
            key_name = normalized_key(str(key))
            child_path = path + (key_name,)
            if key_name in SENSITIVE_KEYS:
                sanitized[key] = REDACTED
            elif kind.casefold() == "secret" and key_name in {"data", "stringdata"}:
                sanitized[key] = REDACTED
            elif named_credential and key_name == "value":
                sanitized[key] = REDACTED
            else:
                sanitized[key] = sanitize_value(child, kind, child_path)
        return sanitized
    if isinstance(value, list):
        return [sanitize_value(item, parent_kind, path) for item in value]
    if isinstance(value, str):
        if EMBEDDED_YAML_SECRET_PATTERN.search(value):
            raise UnsafeEvidenceError("embedded YAML Secret rejected")
        stripped = value.strip()
        if stripped.startswith(("{", "[")):
            try:
                decoded = load_json(value)
            except UnsafeEvidenceError as error:
                raise UnsafeEvidenceError("malformed embedded JSON rejected") from error
            else:
                return json.dumps(
                    sanitize_value(decoded, parent_kind, path),
                    separators=(",", ":"),
                    sort_keys=True,
                )
        return sanitize_text(value)
    return value


def sanitize_text(text: str) -> str:
    if CONTROL_CHARACTER_PATTERN.search(text):
        raise UnsafeEvidenceError("disallowed control character rejected")
    if PRIVATE_KEY_PATTERN.search(text):
        raise UnsafeEvidenceError("private key material rejected")
    if EMBEDDED_YAML_SECRET_PATTERN.search(text):
        raise UnsafeEvidenceError("embedded YAML Secret rejected")
    sanitized = AUTHORIZATION_PATTERN.sub(lambda match: match.group(1) + REDACTED, text)
    sanitized = BEARER_PATTERN.sub(lambda match: match.group(1) + REDACTED, sanitized)
    sanitized = GITHUB_TOKEN_PATTERN.sub(REDACTED, sanitized)
    return TEXT_CREDENTIAL_PATTERN.sub(lambda match: match.group(1) + REDACTED, sanitized)


def read_text(source: Path) -> str:
    try:
        text = source.read_text(encoding="utf-8")
    except UnicodeDecodeError as error:
        raise UnsafeEvidenceError("binary or non-UTF-8 evidence rejected") from error
    sanitize_text(text)
    return text


def sanitize_file(source: Path, destination: Path) -> None:
    if source.name not in ALLOWED_FILES:
        raise UnsafeEvidenceError(f"unexpected evidence artifact rejected: {source.name}")
    if source.is_symlink() or not source.is_file():
        raise UnsafeEvidenceError(f"non-regular evidence artifact rejected: {source.name}")
    if source.stat().st_nlink != 1:
        raise UnsafeEvidenceError(f"hard-linked evidence artifact rejected: {source.name}")
    decoded = load_json(read_text(source))
    destination.write_text(
        json.dumps(sanitize_value(decoded), indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )


def assert_sanitized(root: Path) -> None:
    for path in root.iterdir():
        if path.name not in ALLOWED_FILES or path.is_symlink() or not path.is_file():
            raise UnsafeEvidenceError(f"unexpected sanitized output: {path.name}")
        decoded = load_json(read_text(path))
        sanitized = sanitize_value(decoded)
        if decoded != sanitized:
            raise UnsafeEvidenceError(f"sensitive value remains in {path.name}")


def sanitize_directory(source: Path, destination: Path) -> None:
    if source.is_symlink() or not source.is_dir():
        raise UnsafeEvidenceError("source must be a regular evidence directory")
    if destination.exists() or destination.is_symlink():
        raise UnsafeEvidenceError("destination already exists")
    entries = list(source.iterdir())
    if not any(path.name == "metadata.json" for path in entries):
        raise UnsafeEvidenceError("metadata.json is required")

    destination.parent.mkdir(parents=True, exist_ok=True)
    temporary = Path(tempfile.mkdtemp(prefix=".sanitize-evidence-", dir=destination.parent))
    try:
        for path in entries:
            if path.is_dir():
                raise UnsafeEvidenceError(f"nested evidence directory rejected: {path.name}")
            sanitize_file(path, temporary / path.name)
        metadata_path = temporary / "metadata.json"
        metadata = load_json(metadata_path.read_text(encoding="utf-8"))
        if "environment.json" in {path.name for path in entries}:
            metadata["environmentSha256"] = hashlib.sha256(
                (temporary / "environment.json").read_bytes()
            ).hexdigest()
        if "scan-input.json" in {path.name for path in entries}:
            metadata["capturedInputSha256"] = hashlib.sha256(
                (temporary / "scan-input.json").read_bytes()
            ).hexdigest()
        metadata_path.write_text(
            json.dumps(metadata, indent=2, sort_keys=True) + "\n", encoding="utf-8"
        )
        assert_sanitized(temporary)
        temporary.replace(destination)
    except Exception:
        shutil.rmtree(temporary, ignore_errors=True)
        raise


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("destination", type=Path)
    args = parser.parse_args()
    source = args.source.absolute()
    destination = args.destination.absolute()
    if destination == source or source in destination.parents:
        parser.error("destination must not be inside the source directory")
    try:
        sanitize_directory(source, destination)
    except UnsafeEvidenceError as error:
        print(f"evidence sanitization failed: {error}")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
