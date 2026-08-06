#!/usr/bin/env python3
"""Replace shared allocatable stencil scratch with private fixed-size arrays."""

from __future__ import annotations

import argparse
from pathlib import Path
import re


DECLARATION = re.compile(
    r"^(?P<indent>\s*)real\(kind\s*=\s*wp\),\s*dimension\(:\),\s*"
    r"allocatable,\s*save\s*::\s*(?P<names>[^!\n]+)(?P<comment>\s*!.*)?$",
    re.IGNORECASE,
)
ALLOCATION = re.compile(
    r"^\s*if\s*\(\s*\.not\.\s*allocated\s*\(\s*"
    r"(?:Jq_xU|Jr_xU|Js_xU|Ufx|Ubx)\s*\)\s*\)\s*"
    r"allocate\s*\(\s*(?:Jq_xU|Jr_xU|Js_xU|Ufx|Ubx)\s*\(\s*n\s*\)\s*\)\s*$",
    re.IGNORECASE,
)
EXPECTED_DECLARATIONS = 17
EXPECTED_ALLOCATIONS = 53


def transform(source: str) -> tuple[str, int, int]:
    output: list[str] = []
    declarations = 0
    allocations = 0

    for line in source.splitlines():
        declaration = DECLARATION.match(line)
        if declaration and "jq_xu" in declaration.group("names").lower():
            names = declaration.group("names").rstrip()
            comment = declaration.group("comment") or ""
            output.append(
                f"{declaration.group('indent')}real(kind = wp), dimension(9) :: "
                f"{names}{comment}"
            )
            declarations += 1
            continue
        if ALLOCATION.match(line):
            allocations += 1
            continue
        output.append(line)

    return "\n".join(output) + "\n", declarations, allocations


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()

    original = args.source.read_text()
    updated, declarations, allocations = transform(original)
    if declarations != EXPECTED_DECLARATIONS or allocations != EXPECTED_ALLOCATIONS:
        raise SystemExit(
            "refusing transformation: expected "
            f"{EXPECTED_DECLARATIONS} declarations/{EXPECTED_ALLOCATIONS} allocations, "
            f"found {declarations}/{allocations}"
        )
    if updated == original:
        raise SystemExit("source already transformed or no changes produced")

    print(f"validated declarations: {declarations}")
    print(f"validated allocation statements: {allocations}")
    if args.apply:
        args.source.write_text(updated)
        print(f"updated: {args.source}")
    else:
        print("dry run only; pass --apply to update")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

