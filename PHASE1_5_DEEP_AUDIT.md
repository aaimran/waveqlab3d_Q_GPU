# Phases 1-5 deep audit

Date: 2026-08-06  
Status: complete; confirmed defects fixed and requalified

## Audit scope

The audit followed the complete execution chain: CMake backend selection,
MPI-local device binding, capacity enforcement, persistent allocation and
accounting, generated leaf ownership, RK transfers, raw-array descriptors,
Phase 5 eligibility/fallback, numerical diagnostics, and CPU/H100 coverage.

## Confirmed defects and fixes

### Phase 1: ignored CPU MPI status

The CPU accelerator runtime did not check the return from
`MPI_Comm_rank(MPI_COMM_WORLD,...)`. It now uses the same fatal MPI status
handling as the OpenACC runtime and subsequent communicator operations.

### Phase 3: incomplete host-update ownership guard

The explicit host-update traversal checked presence per leaf but did not check
its aggregate against active ownership. It now rejects any traversal whose
leaf count or payload exceeds active persistent ownership. The generator
contains the same rule, and regeneration drift-check passes.

### Phase 5: ghost-cell storage indices were wrong

This was the material numerical defect. A physical `41^3` block is stored as a
`47^3` allocatable array with bounds `-2:44`. Passing it to an explicit-shape
raw kernel remaps storage to `1:47`. The original kernel looped over raw
`7:41`, although the CPU strict interior is physical `7:35`, which maps to raw
`10:38`.

The old four-digit maximum did not expose the shifted and oversized GPU region
because the source/boundary peak dominated. The wrapper now converts physical
bounds through each allocatable lower bound and passes raw `10:38`. Shape,
lower-bound, allocation, stencil, physics, PML, operator, mesh, and one-rank
conditions are guarded before dispatch. Unsupported cases use the CPU routine.

NVHPC also evaluated array-result shape/lower-bound comparisons incorrectly in
this derived-allocatable eligibility path, causing valid cases to fall back.
Scalar dimension/bound comparisons replaced them. Optional
`WQL3D_PHASE5_DIAGNOSTICS=1` reports resolved bounds once.

### Phase 5: weak oracle precision and fallback coverage

Final diagnostics used four digits, allowing the index defect to escape the
decomposition oracle. They now print 16 digits; one-rank GPU and two-rank CPU
fallback results match at that precision.

Two negative-path H100 tests prove that traditional-upwind and Q8 inputs finish
without launching the Phase 5 kernel. The positive test requires all 30
launches to use the corrected `29^3` geometry: 191 gangs and vector length 128.

## Requalification

| Gate | Result |
|---|---:|
| Generated device traversal | 158/158 declarations |
| Persistent inventory | 178 declarations |
| RK normalization | 49 scale + 49 update calls |
| RK-reachable allocation audit | 140 procedures, no allocation |
| Transfer audit | 6 calls confined to Phase 4/5 bridges |
| Modern NVHPC/H100 suite | 31/31, 167.04 s |
| Modern NVHPC CPU-release suite | 23/23, 114.71 s |
| NVHPC CPU allocation-audit subset | 4/4, 106.36 s |
| Corrected Phase 5 Compute Sanitizer memcheck | zero errors |
| Corrected Phase 5 Compute Sanitizer racecheck | zero hazards/errors/warnings |

Corrected output-disabled six-step timing was 0.658815 s on NVHPC CPU
(0.109803 s/step) and 0.824372 s on the hybrid H100 path (0.137395 s/step).
This is not a speedup claim; synchronization and host boundary/source/SAT work
still dominate.

## Remaining intentional fallbacks

- Phase 5 GPU dispatch requires one MPI rank, traditional order 6, Cartesian
  nine-field elasticity, no attenuation, and no PML.
- Multi-rank, upwind/DRP, attenuation, PML, curvilinear, fault/interface, and
  plastic configurations retain the CPU spatial RHS.
- Near-boundary SBP, source, SAT/interface, and MPI work remains on the host;
  the rate download after the strict-interior kernel is explicit and audited.
- CUDA-aware MPI remains disabled.

No additional Phase 1-4 numerical defect was found after static analysis,
broad regressions, allocation tracking, notification, and sanitizer checks.
