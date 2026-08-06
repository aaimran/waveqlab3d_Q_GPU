#!/usr/bin/env python3
"""Reject explicit allocation in the transitive RK steady-state call graph."""

from __future__ import annotations

import argparse
import re
from collections import defaultdict, deque
from dataclasses import dataclass
from pathlib import Path


START_RE = re.compile(r"^\s*(?:[a-z][\w\s(),=*]*\s+)?(subroutine|function)\s+([a-z]\w*)\b", re.I)
END_RE = re.compile(r"^\s*end\s+(subroutine|function)\b", re.I)
CALL_RE = re.compile(r"\bcall\s+([a-z]\w*)\b", re.I)
ALLOC_RE = re.compile(r"\b(deallocate|allocate)\s*\(", re.I)


@dataclass(frozen=True)
class Procedure:
    name: str
    path: Path
    start: int
    lines: tuple[str, ...]


def logical_code(line: str) -> str:
    return line.split("!", 1)[0]


def parse_file(path: Path) -> list[Procedure]:
    lines = path.read_text(encoding="utf-8").splitlines()
    procedures: list[Procedure] = []
    current_name: str | None = None
    current_start = 0
    current_lines: list[str] = []

    for number, line in enumerate(lines, 1):
        code = logical_code(line)
        if current_name is None:
            match = START_RE.match(code)
            if match:
                current_name = match.group(2).lower()
                current_start = number
                current_lines = [line]
        else:
            current_lines.append(line)
            if END_RE.match(code):
                procedures.append(Procedure(current_name, path, current_start, tuple(current_lines)))
                current_name = None
                current_lines = []
    return procedures


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", default="time_step_rk")
    parser.add_argument("--source-dir", type=Path, default=Path("src"))
    args = parser.parse_args()

    by_name: dict[str, list[Procedure]] = defaultdict(list)
    for path in sorted(args.source_dir.glob("*.f90")):
        if path.name in {
            "original_RHS_interior.f90",
            "BoundaryConditions2.f90",
            "BoundaryConditions3.f90",
        } or path.name.endswith(".bak"):
            continue
        for procedure in parse_file(path):
            by_name[procedure.name].append(procedure)

    root = args.root.lower()
    if root not in by_name:
        raise SystemExit(f"steady-state root not found: {root}")

    reachable: set[Procedure] = set()
    pending = deque(by_name[root])
    while pending:
        procedure = pending.popleft()
        if procedure in reachable:
            continue
        reachable.add(procedure)
        body = "\n".join(logical_code(line) for line in procedure.lines)
        for called in CALL_RE.findall(body):
            pending.extend(by_name.get(called.lower(), ()))

    violations: list[str] = []
    for procedure in sorted(reachable, key=lambda item: (str(item.path), item.start)):
        for offset, line in enumerate(procedure.lines):
            if ALLOC_RE.search(logical_code(line)):
                violations.append(
                    f"{procedure.path}:{procedure.start + offset}: {procedure.name}: {line.strip()}"
                )

    if violations:
        print("FAIL: explicit allocation is reachable from time_step_RK")
        print("\n".join(violations))
        return 1

    print(f"PASS: {len(reachable)} RK-reachable procedures contain no explicit allocate/deallocate")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
