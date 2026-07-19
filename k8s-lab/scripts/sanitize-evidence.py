#!/usr/bin/env python3
"""Prepare a fail-closed sanitized copy of a RADAR evidence directory."""

from __future__ import annotations

import argparse
import json
import re
import shutil
import tempfile
from pathlib import Path
from typing import Any

import yaml


REDACTED = "<redacted>"
ALLOWED_SUFFIXES = {".csv", ".json", ".log", ".sha256", ".txt", ".yaml", ".yml"}
IMAGE_SUFFIXES = {".bmp", ".gif", ".jpeg", ".jpg", ".png", ".tif", ".tiff", ".webp"}
SENSITIVE_KEYS = {
    "accesstoken",
    "authorization",
    "certificateauthoritydata",
    "clientcertificate",
    "clientcertificatedata",
    "clientkey",
    "clientkeydata",
    "clientsecret",
    "idtoken",
    "password",
    "privatekey",
    "refreshtoken",
    "sshprivatekey",
    "token",
}
PRIVATE_KEY_PATTERN = re.compile(r"-----BEGIN (?:OPENSSH|RSA|EC|DSA)? ?PRIVATE KEY-----")
AUTHORIZATION_PATTERN = re.compile(
    r"(?i)(authorization\s*[:=]\s*)(?:bearer\s+)?[A-Za-z0-9._~+/=-]{8,}"
)
BEARER_PATTERN = re.compile(r"(?i)(bearer\s+)[A-Za-z0-9._~+/=-]{8,}")
GITHUB_TOKEN_PATTERN = re.compile(r"\b(?:ghp|github_pat)_[A-Za-z0-9_]{20,}\b")
TEXT_CREDENTIAL_PATTERN = re.compile(
    r"(?im)^(\s*(?:access[-_ ]?token|authorization|client[-_ ]?secret|client[-_ ]?key[-_ ]?data|"
    r"client[-_ ]?certificate[-_ ]?data|password|private[-_ ]?key|refresh[-_ ]?token|token)"
    r"\s*[:=]\s*)(?!<redacted>\s*$)(?:\"[^\"\r\n]*\"|'[^'\r\n]*'|[^\s#]+)"
)


class UnsafeEvidenceError(ValueError):
    """Raised when an input cannot be sanitized with the declared rules."""


def normalized_key(value: str) -> str:
    return re.sub(r"[^a-z0-9]", "", value.lower())


def sanitize_value(value: Any, parent_kind: str = "") -> Any:
    if isinstance(value, dict):
        declared_kind = value.get("kind", parent_kind)
        kind = declared_kind if isinstance(declared_kind, str) else parent_kind
        sanitized: dict[Any, Any] = {}
        for key, child in value.items():
            key_name = normalized_key(str(key))
            if key_name in SENSITIVE_KEYS:
                sanitized[key] = REDACTED
            elif kind.casefold() == "secret" and key_name in {"data", "stringdata"}:
                sanitized[key] = REDACTED
            else:
                sanitized[key] = sanitize_value(child, kind)
        return sanitized
    if isinstance(value, list):
        return [sanitize_value(item, parent_kind) for item in value]
    if isinstance(value, str):
        stripped = value.strip()
        if stripped.startswith(("{", "[")):
            try:
                decoded = json.loads(value)
            except json.JSONDecodeError:
                pass
            else:
                return json.dumps(
                    sanitize_value(decoded, parent_kind),
                    separators=(",", ":"),
                    sort_keys=True,
                )
        return sanitize_text(value)
    return value


def sanitize_text(text: str) -> str:
    if "\x00" in text:
        raise UnsafeEvidenceError("NUL bytes are not permitted in text evidence")
    if PRIVATE_KEY_PATTERN.search(text):
        raise UnsafeEvidenceError("private key material cannot be sanitized reliably")
    sanitized = AUTHORIZATION_PATTERN.sub(lambda match: match.group(1) + REDACTED, text)
    sanitized = BEARER_PATTERN.sub(lambda match: match.group(1) + REDACTED, sanitized)
    sanitized = GITHUB_TOKEN_PATTERN.sub(REDACTED, sanitized)
    sanitized = TEXT_CREDENTIAL_PATTERN.sub(lambda match: match.group(1) + REDACTED, sanitized)
    return sanitized


def read_text(source: Path) -> str:
    try:
        text = source.read_text(encoding="utf-8")
    except UnicodeDecodeError as error:
        raise UnsafeEvidenceError(f"binary or non-UTF-8 file rejected: {source}") from error
    if "\x00" in text:
        raise UnsafeEvidenceError(f"binary file rejected: {source}")
    return text


def sanitize_file(source: Path, destination: Path) -> None:
    if source.is_symlink():
        raise UnsafeEvidenceError(f"symbolic link rejected: {source}")
    if not source.is_file():
        raise UnsafeEvidenceError(f"non-regular file rejected: {source}")

    suffix = source.suffix.lower()
    if suffix in IMAGE_SUFFIXES:
        raise UnsafeEvidenceError(f"image evidence requires manual review and is rejected: {source}")
    if suffix not in ALLOWED_SUFFIXES:
        raise UnsafeEvidenceError(f"unsupported evidence format rejected: {source}")

    text = read_text(source)
    destination.parent.mkdir(parents=True, exist_ok=True)
    if suffix == ".json":
        try:
            decoded = json.loads(text)
        except json.JSONDecodeError as error:
            raise UnsafeEvidenceError(f"invalid JSON rejected: {source}") from error
        destination.write_text(
            json.dumps(sanitize_value(decoded), indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
    elif suffix in {".yaml", ".yml"}:
        try:
            documents = list(yaml.safe_load_all(text))
        except yaml.YAMLError as error:
            raise UnsafeEvidenceError(f"invalid YAML rejected: {source}") from error
        sanitized_documents = [sanitize_value(document) for document in documents]
        destination.write_text(
            yaml.safe_dump_all(sanitized_documents, sort_keys=True),
            encoding="utf-8",
        )
    else:
        destination.write_text(sanitize_text(text), encoding="utf-8")


def assert_sanitized(root: Path) -> None:
    for path in root.rglob("*"):
        if path.is_symlink():
            raise UnsafeEvidenceError(f"symbolic link found after sanitization: {path}")
        if path.is_dir():
            continue
        if not path.is_file() or path.suffix.lower() not in ALLOWED_SUFFIXES:
            raise UnsafeEvidenceError(f"unexpected sanitized output: {path}")
        text = read_text(path)
        if PRIVATE_KEY_PATTERN.search(text):
            raise UnsafeEvidenceError(f"private key material remains in {path}")
        if AUTHORIZATION_PATTERN.search(text) or BEARER_PATTERN.search(text):
            raise UnsafeEvidenceError(f"authorization credential remains in {path}")
        if GITHUB_TOKEN_PATTERN.search(text):
            raise UnsafeEvidenceError(f"GitHub credential remains in {path}")
        if TEXT_CREDENTIAL_PATTERN.search(text):
            raise UnsafeEvidenceError(f"credential assignment remains in {path}")
        if path.suffix.lower() == ".json":
            json.loads(text)
        elif path.suffix.lower() in {".yaml", ".yml"}:
            list(yaml.safe_load_all(text))


def sanitize_directory(source: Path, destination: Path) -> None:
    if source.is_symlink() or not source.is_dir():
        raise UnsafeEvidenceError("source must be a regular evidence directory")
    if destination.exists() or destination.is_symlink():
        raise UnsafeEvidenceError(f"destination already exists: {destination}")

    destination.parent.mkdir(parents=True, exist_ok=True)
    temporary = Path(tempfile.mkdtemp(prefix=".sanitize-evidence-", dir=destination.parent))
    try:
        for path in source.rglob("*"):
            relative = path.relative_to(source)
            target = temporary / relative
            if path.is_symlink():
                raise UnsafeEvidenceError(f"symbolic link rejected: {path}")
            if path.is_dir():
                target.mkdir(parents=True, exist_ok=True)
            elif path.is_file():
                sanitize_file(path, target)
            else:
                raise UnsafeEvidenceError(f"non-regular evidence entry rejected: {path}")
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
