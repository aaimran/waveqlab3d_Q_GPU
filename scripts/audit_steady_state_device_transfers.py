#!/usr/bin/env python3
"""Reject explicit device-data movement in the transitive RK call graph."""

from __future__ import annotations

import argparse
import re
from collections import defaultdict, deque
from pathlib import Path

from audit_steady_state_allocations import CALL_RE, Procedure, logical_code, parse_file


RUNTIME_TRANSFER = re.compile(
    r"\bacc_(?:copyin|pcopyin|create|pcreate|copyout|delete|update|memcpy|map_data|unmap_data)\b",
    re.I,
)
DIRECTIVE_TRANSFER = re.compile(r"^\s*!\$acc\s+(?:enter\s+data|exit\s+data|update)\b", re.I)
EXCLUDED = {"original_RHS_interior.f90", "BoundaryConditions2.f90", "BoundaryConditions3.f90"}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", default="time_step_rk")
    parser.add_argument("--source-dir", type=Path, default=Path("src"))
    args = parser.parse_args()

    by_name: dict[str, list[Procedure]] = defaultdict(list)
    for path in sorted(args.source_dir.glob("*.f90")):
        if path.name in EXCLUDED or path.name.endswith(".bak"):
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
            if RUNTIME_TRANSFER.search(logical_code(line)) or DIRECTIVE_TRANSFER.search(line):
                violations.append(
                    f"{procedure.path}:{procedure.start + offset}: {procedure.name}: {line.strip()}"
                )
    if violations:
        print("FAIL: explicit device transfer is reachable from time_step_RK")
        print("\n".join(violations))
        return 1
    print(f"PASS: {len(reachable)} RK-reachable procedures contain no explicit device transfer")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
