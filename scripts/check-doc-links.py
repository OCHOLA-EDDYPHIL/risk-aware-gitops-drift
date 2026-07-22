#!/usr/bin/env python3
"""Fail when a repository Markdown link points to a missing local file."""

from __future__ import annotations

import re
import sys
from pathlib import Path
from urllib.parse import unquote


ROOT = Path(__file__).resolve().parents[1]
LINK = re.compile(r"(?<!!)\[[^]]*\]\(([^)]+)\)")
SKIP_PREFIXES = ("http://", "https://", "mailto:", "#")


def main() -> int:
    failures: list[str] = []
    for document in sorted(ROOT.rglob("*.md")):
        if ".git" in document.parts:
            continue
        text = document.read_text(encoding="utf-8")
        for line_number, line in enumerate(text.splitlines(), 1):
            for match in LINK.finditer(line):
                target = match.group(1).strip().split(maxsplit=1)[0].strip("<>")
                if not target or target.startswith(SKIP_PREFIXES):
                    continue
                path_part = unquote(target.split("#", 1)[0])
                if not path_part:
                    continue
                candidate = (document.parent / path_part).resolve()
                if not candidate.exists() or not candidate.is_relative_to(ROOT):
                    failures.append(f"{document.relative_to(ROOT)}:{line_number}: {target}")
    if failures:
        print("Broken or out-of-repository Markdown links:", file=sys.stderr)
        for failure in failures:
            print(f"  {failure}", file=sys.stderr)
        return 1
    print("Repository Markdown links are valid.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
