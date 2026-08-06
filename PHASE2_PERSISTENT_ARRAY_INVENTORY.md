# Phase 2 persistent-array inventory

Date: 2026-08-06  
Status: structural inventory and runtime payload accounting implemented; capacity enforcement pending

## Purpose

Phase 3 must not rely on an implicit OpenACC deep copy of `domain_type`.
Every allocatable leaf therefore needs an explicit owner and transfer policy
before a persistent device data region is introduced.

The reproducible inventory is generated from the canonical derived-type
definitions in `src/datatypes.f90`:

```bash
python3 scripts/inventory_persistent_arrays.py
python3 scripts/inventory_persistent_arrays.py --check
```

The first command emits a Markdown table with one row per allocatable
component. The check mode fails if parsing breaks or the inventory becomes
unexpectedly incomplete.

## Current coverage

The inventory contains 174 allocatable components:

| Owner | Components |
|---|---:|
| `block_material` | 99 |
| `moment_tensor` | 20 |
| `iface_type` | 15 |
| `block_boundary` | 11 |
| `seismogram_type` | 8 |
| `block_grid_t` | 5 |
| `domain_type` | 4 |
| `block_type` | 3 |
| `plane_output_plane` | 3 |
| `block_fields` | 2 |
| `block_pml` | 2 |
| `block_plastic` | 1 |
| `plane_output_type` | 1 |

Every emitted row records:

- owner and component name;
- declared type, rank, and shape;
- numerical or orchestration role;
- proposed OpenACC policy (`copyin`, `create`, `host/update`, or explicit
  traversal of child leaves);
- initialization and mutation locations;
- communication and output requirements.

The initial policy classification is:

| Policy | Components | Meaning |
|---|---:|---|
| `create` | 118 | Device-resident state, rate, attenuation, PML, or scratch storage |
| `copyin` | 40 | Initialized host data copied once and normally immutable on device |
| `host` | 8 | Host orchestration/output metadata |
| `host/update` | 4 | Host output buffers populated explicitly from device data |
| `explicit leaves` | 4 | Allocatable ownership containers; never deep-copied implicitly |

## Safety boundary

This is a source-structure inventory, not yet a capacity estimate. Declared
shapes are assumed-shape descriptors; exact bytes depend on the resolved MPI
decomposition, enabled physics, PML, attenuation model, source count, and
output configuration.

Runtime traversal of allocated leaves now reports:

1. total persistent host bytes per rank;
2. predicted persistent device bytes per rank;
3. bytes grouped by grid, material, state/rate, PML, interface, and output;
4. maximum and aggregate MPI-rank totals;
5. predicted device payload before device entry.

The accounting implementation is in `src/persistent_memory.f90`. Unallocated
components contribute zero, so one code path covers elastic, attenuation, PML,
plasticity, sources, interfaces, faults, and optional outputs. Derived-type
descriptors and compiler/runtime allocator overhead are intentionally excluded;
the reported values are persistent array payload bytes.

Local GNU debug measurements for one 41-cubed block were:

| Category | Elastic O6 | Anelastic Q8 |
|---|---:|---:|
| grid/metric | 10.297 MiB | 10.297 MiB |
| material/attenuation | 2.376 MiB | 80.003 MiB |
| field state/rate | 14.258 MiB | 14.258 MiB |
| boundary/workspace | 5.402 MiB | 5.402 MiB |
| predicted device payload/rank | 32.334 MiB | 109.961 MiB |

Both the Q8 and elastic one-rank/two-rank regressions passed after accounting
was enabled. The remaining memory subgate is capacity enforcement with a
documented reserve for OpenACC runtime, MPI, temporary kernels, and allocator
fragmentation.
