# Phase 6 boundary, SAT, and compact PML

## Status

Phase 6A has started with the deliberately narrow one-rank, one-block,
traditional order-6 Cartesian `Lx` characteristic boundary.  Boundary forcing
preparation and the SAT rate addition execute in one face-local OpenACC kernel.
The physical `41 x 41` face is translated through the `-2:44` ghost-backed
normal storage; the qualified launch uses 14 gangs and vector length 128.

The backend preserves the CPU implementation as an explicit fallback.  It
declines MMS, PML, multiple active physical faces, multiple ranks, other finite
difference families/orders, unexpected component counts, invalid face/storage
shapes, and absent allocations.  Device presence is checked before launch.

The one-face H100 result matches the CPU final-state oracle at 16 digits:

```text
Elastic final state: max|field|=  1.6623128367649574E+02
```

## Remaining Phase 6 work

- Qualify the other five physical faces and all three boundary modes.
- Add after-every-stage `F`, `DF`, face-forcing, `Q`, and `DQ` comparisons.
- Port compact PML in the required one-face, opposing-face, edge, corner, and
  all-face sequence, followed by its terminal boundary treatment.
- Add PML memory/time counters, reflection cases, long-time energy, transfer
  auditing, and Compute Sanitizer qualification.

PML remains on the audited host fallback until those gates pass; no scientific
GPU claim is made for Phase 6 yet.
