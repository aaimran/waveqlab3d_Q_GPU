#!/usr/bin/env python3
"""Inventory allocatable components that define persistent solver ownership."""

from __future__ import annotations

import argparse
import re
from pathlib import Path


TYPE_START = re.compile(r"^\s*type\s*(?:,.*)?::\s*(\w+)", re.I)
TYPE_END = re.compile(r"^\s*end\s*type", re.I)
DECLARATION = re.compile(r"^\s*(.+?)\s*::\s*(.+)$")
DIMENSION = re.compile(r"dimension\s*\(([^)]*)\)", re.I)


def logical_lines(text: str) -> list[str]:
    result: list[str] = []
    pending = ""
    for raw in text.splitlines():
        code = raw.split("!", 1)[0].strip()
        if not code:
            continue
        if pending:
            code = code.removeprefix("&").lstrip()
            pending += " " + code
        else:
            pending = code
        if pending.endswith("&"):
            pending = pending[:-1].rstrip()
            continue
        result.append(pending)
        pending = ""
    if pending:
        result.append(pending)
    return result


def split_components(text: str) -> list[str]:
    result: list[str] = []
    token = ""
    depth = 0
    for character in text:
        if character == "(":
            depth += 1
        elif character == ")":
            depth -= 1
        if character == "," and depth == 0:
            result.append(token.strip())
            token = ""
        else:
            token += character
    if token.strip():
        result.append(token.strip())
    return result


def policy(owner: str, name: str) -> tuple[str, str, str, str, str, str]:
    key = f"{owner}.{name}".lower()
    if owner == "block_grid_t":
        return "grid/metric", "copyin", "grid.f90", "immutable", "halo geometry", "none"
    if owner == "block_fields":
        role = "rate" if name.lower() == "df" else "state"
        return role, "create", "fields.f90", "RK stages", "halo exchange", "field/station output"
    if owner == "block_material":
        if name.lower().startswith("deta"):
            return "attenuation rate", "create", "material.f90", "RK stages", "halo exchange", "diagnostics"
        if name.lower().startswith("eta"):
            return "attenuation state", "create", "material.f90", "RK stages", "halo exchange", "diagnostics"
        return "material", "copyin", "material.f90", "initialization", "boundary/interface", "none"
    if owner == "block_pml":
        role = "PML rate" if name.lower() == "dq" else "PML state"
        return role, "create", "pml.f90", "RK stages", "local", "none"
    if owner == "block_plastic":
        return "plastic state", "create", "plastic_material.f90", "RK stages", "halo exchange", "diagnostics"
    if owner == "block_boundary":
        return "boundary mirror", "create", "boundary.f90", "SAT/RK stages", "boundary/interface", "none"
    if owner == "block_type" and name.startswith("work_"):
        return "SAT workspace", "create", "block.f90", "RK stages", "local", "none"
    if owner == "iface_type":
        role = "interface workspace" if name.startswith("work_") else "interface state/rate"
        return role, "create", "iface.f90", "interface/RK stages", "paired interface ranks", "fault diagnostics"
    if owner == "moment_tensor":
        return "source metadata/work", "copyin", "moment_tensor.f90", "source injection", "source owner", "optional exact source"
    if owner == "fault_type":
        return "fault output mirror", "host/update", "fault_output.f90", "output sampling", "fault communicator", "fault output"
    if owner == "seismogram_type":
        return "station metadata", "host", "seismogram.f90", "output sampling", "none", "seismograms"
    if owner in {"plane_output_plane", "plane_output_type"}:
        return "plane output", "host/update", "plane_output.f90", "output sampling", "none", "plane output"
    if owner == "domain_type":
        return "ownership container", "explicit leaves", "domain.f90", "orchestration", "MPI domain", "mixed"
    return "host metadata", "host", "initialization", "orchestration", "none", "none"


def inventory(path: Path) -> list[tuple[str, ...]]:
    rows: list[tuple[str, ...]] = []
    owner = ""
    for line in logical_lines(path.read_text()):
        start = TYPE_START.match(line)
        if start:
            owner = start.group(1)
            continue
        if TYPE_END.match(line):
            owner = ""
            continue
        if not owner or "allocatable" not in line.lower():
            continue
        declaration = DECLARATION.match(line)
        if not declaration:
            continue
        attributes, components = declaration.groups()
        type_name = attributes.split(",", 1)[0].strip()
        common_dimension = DIMENSION.search(attributes)
        common_shape = common_dimension.group(1) if common_dimension else ""
        for component in split_components(components):
            component = component.split("=", 1)[0].strip()
            match = re.match(r"(\w+)\s*(?:\(([^)]*)\))?$", component)
            if not match:
                raise ValueError(f"cannot parse component: {owner}: {component}")
            name, own_shape = match.groups()
            shape = own_shape or common_shape or "scalar"
            rank = 0 if shape == "scalar" else shape.count(",") + 1
            rows.append((owner, name, type_name, str(rank), shape, *policy(owner, name)))
    return rows


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", nargs="?", default="src/datatypes.f90")
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    rows = inventory(Path(args.source))
    if args.check:
        if len(rows) < 100:
            raise SystemExit(f"inventory unexpectedly small: {len(rows)} components")
        print(f"PASS: {len(rows)} persistent allocatable components")
        return 0
    headings = ("Owner", "Component", "Type", "Rank", "Declared shape", "Role",
                "Device policy", "Initialized", "Mutated", "Communication", "Output")
    print("| " + " | ".join(headings) + " |")
    print("|" + "---|" * len(headings))
    for row in rows:
        print("| " + " | ".join(row) + " |")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
