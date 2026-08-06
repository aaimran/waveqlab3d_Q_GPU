#!/usr/bin/env python3
"""Replace whole-array RK expressions with qualified backend kernel calls."""

from __future__ import annotations

import argparse
import re
from pathlib import Path


SCALE = re.compile(r"(?m)^(\s*)(F%[^\s=]+)\s*=\s*A\*(\2)\s*$")
UPDATE = re.compile(r"(?m)^(\s*)(F%[^\s=]+)\s*=\s*\2\s*\+\s*dt\*(F%[^\s]+)\s*$")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("path", nargs="?", type=Path, default=Path("src/fields.f90"))
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()
    text = args.path.read_text()
    scale_count = len(SCALE.findall(text))
    update_count = len(UPDATE.findall(text))
    if (scale_count == 0 and update_count == 0):
        if text.count("call scale_rate_array(") != 49 or text.count("call update_state_array(") != 49:
            raise SystemExit("normalized RK vector call count is unexpected")
        print("PASS: 49 scale and 49 update expressions are backend kernel calls")
        return 0
    if scale_count != 49 or update_count != 49:
        raise SystemExit(f"unexpected RK expression layout: scale={scale_count}, update={update_count}")
    transformed = SCALE.sub(lambda m: f"{m.group(1)}call scale_rate_array({m.group(2)}, A)", text)
    transformed = UPDATE.sub(
        lambda m: f"{m.group(1)}call update_state_array({m.group(2)}, {m.group(3)}, dt)", transformed
    )
    if not args.apply:
        print("PASS: found 49 scale and 49 update expressions; use --apply")
        return 0
    args.path.write_text(transformed)
    print("Applied 49 scale and 49 update kernel-call replacements")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
