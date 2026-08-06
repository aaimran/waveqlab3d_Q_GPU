# Phase 2 scratch and allocation audit

Date: 2026-08-06  
Status: point-stencil scratch corrected; persistent face ownership and accounting implemented

## Audit scope

The source was searched for mutable `save` objects and allocation/deallocation
sites, then classified by whether they are reachable during RK stages.

The tree contains approximately 307 allocation/deallocation statements. The
largest concentrations are initialization-oriented grid, material, PML, and
MPI setup modules. Allocation presence alone is not a defect; allocations in a
grid-point or RK-stage hot path are the immediate GPU risk.

## Corrected point-stencil scratch

Seventeen point derivative routines in `JU_xJU_yJU_z6.f90` declared procedure
local arrays such as:

```fortran
real(kind=wp), dimension(:), allocatable, save :: Jq_xU, Jr_xU, Js_xU
```

They performed first-call allocation from inside routines invoked at grid
points. This design has three problems:

- `save` creates shared mutable procedure state;
- it is unsafe when grid points execute concurrently;
- allocation state and device ownership are unsuitable for GPU device
  routines.

WaveQLab3D's elastic formulation has exactly nine velocity/stress components.
The work arrays are now fixed-size procedure-local arrays:

```fortran
real(kind=wp), dimension(9) :: Jq_xU, Jr_xU, Js_xU
```

All 53 associated first-call allocation statements were removed. One upwind
routine also uses private nine-element `Ufx` and `Ubx` arrays.

The checked transformation is reproducible with:

```bash
python3 scripts/normalize_stencil_scratch.py \
  src/JU_xJU_yJU_z6.f90 --apply
```

The script refuses to modify an unexpected generated-source layout unless it
finds exactly 17 declarations and 53 allocation statements.

## Face-sized workspace audit

The original active RK path contained face-sized `allocatable, save` buffers in:

- `RHS_Interior.f90`: physical boundary and interface SAT workspaces;
- `CouplingForcing.f90`: rotated interface fields, hat fields, and MMS vectors.

Inactive or alternative source files also contain saved workspaces:

- `BoundaryConditions2.f90`;
- `original_RHS_interior.f90`.

The face arrays should not be converted blindly to automatic arrays. At
production face sizes, several arrays per call could consume multiple MiB of
thread stack. The safe target is persistent ownership by the block or interface
object, allocated during domain initialization and released during domain
cleanup.

The active instances now have explicit block/interface ownership. Inactive
alternative source files remain unchanged and are not compiled into the
solver.

## Benign saved state

The following module-level saved scalars are intentional process state rather
than grid-point scratch:

- MPI rank, process count, and timing state in `mpi3dbasic.f90`;
- accelerator runtime communicator/device state;
- one-time material summary flags.

They are host-side orchestration state and are not candidates for GPU kernel
privatization.

## Verification completed

After private point-scratch conversion, the standalone GNU debug build passed:

```text
fq8_effective_response_unit    passed
q8_dynamic_decomposition       passed
q4_dynamic_decomposition       passed
```

The selected suite completed in 4.13 seconds with no failures.

## Required next checks

Before closing the scratch subphase:

1. rebuild `cpu-release` and `gpu-h100` with NVHPC on Punakha;
2. repeat fQ8/Q8/Q4 regressions;
3. run short traditional, upwind-6, and upwind-DRP-6 cases because all point
   operator families were mechanically normalized;
4. verify identical receiver/final-state results against the frozen baseline;
5. move active face workspaces into explicit block/interface ownership;
6. add per-owner byte accounting after all persistent owners are explicit.

## Punakha NVHPC confirmation

The private point-stencil scratch conversion passed on Punakha on 2026-08-06:

| Configuration | fQ8 unit | Q8 1/2-rank | Q4 1/2-rank | Total |
|---|---:|---:|---:|---:|
| `cpu-release` | pass | pass, 6.69 s | pass, 5.91 s | 12.61 s |
| `gpu-h100` | pass | pass, 7.83 s | pass, 6.58 s | 14.42 s |

Both builds passed all selected tests. This closes the point-stencil scratch
subgate for the Q4/Q8 traditional cases. Short explicit upwind and upwind-DRP
operator fixtures remain required before those FD families are qualified.

## Persistent face-workspace ownership

The active SAT and interface paths now use explicitly owned persistent
workspaces instead of procedure-local `allocatable, save` arrays:

- each block owns three physical-boundary workspaces;
- each interface owns forcing, rotated-field, and hat-field workspaces;
- allocation occurs during block/interface initialization;
- cleanup occurs in `close_domain` through guarded deallocation;
- non-owning routine dummies are assumed-shape rather than unnecessarily
  requiring allocatable actual arguments.

Local GNU debug verification on 2026-08-06 passed the fQ8 unit and Q8/Q4
one-rank/two-rank decomposition suite. Both 46-step serial friction/interface
smoke runs also completed normally, exercising Cartesian and curvilinear
two-block interfaces and workspace cleanup.

The legacy interface-test harness was repaired for the standalone tree: test
data and checker paths are explicit, required output directories are created,
and `read_binary.py` is Python 3 and standard-library only. Its archived truth
comparison is not qualified locally: the truth corresponds to the historical
four-rank layout, while current decomposition safety rejects splitting these
21-point blocks across four ranks because it violates the 20-point local-grid
minimum. Punakha NVHPC CPU/OpenACC builds and a suitably sized locked numerical
interface fixture remain required before closing this subphase.

Each run now reports block, interface, maximum-per-rank, and aggregate MPI
face-workspace allocation using actual allocated element counts and the
working-real storage size:

| Case | Rank-0 block | Rank-0 interface | Maximum/rank | Aggregate |
|---|---:|---:|---:|---:|
| Q8, one 41-cubed block | 0.346 MiB | 0.000 MiB | 0.346 MiB | 0.346 MiB |
| TPV5, serial two 21-cubed blocks | 0.182 MiB | 0.141 MiB | 0.323 MiB | 0.323 MiB |

## Punakha face-workspace qualification

The persistent face-workspace ownership and accounting changes passed NVHPC
26.5 qualification on Punakha on 2026-08-06:

| Configuration | fQ8 unit | Q8 1/2-rank | Q4 1/2-rank | Total |
|---|---:|---:|---:|---:|
| `cpu-release` | pass | pass, 7.04 s | pass, 5.91 s | 12.96 s |
| `gpu-h100` | pass | pass, 8.08 s | pass, 6.80 s | 14.88 s |

All six selected checks passed. This closes the NVHPC compiler/runtime gate
for persistent face ownership. Numerical kernels are not offloaded yet, so the
`gpu-h100` result qualifies OpenACC compilation and runtime behavior rather
than GPU numerical performance.

## Order-6 finite-difference fixtures

Three short, nonzero elastic moment-source fixtures now exercise every target
order-6 operator family:

- `test_elastic_traditional_o6.in`;
- `test_elastic_upwind_o6.in`;
- `test_elastic_upwind_drp_o6.in`.

Each regression runs with one and two MPI ranks, requires successful shutdown,
a finite nonzero elastic field, and an identical formatted global maximum
across decompositions. Local GNU debug qualification passed on 2026-08-06:

| Family | Test time | Final max field |
|---|---:|---:|
| traditional-6 | 1.18 s | 1.6623E+02 |
| upwind-6 | 1.25 s | 1.6563E+02 |
| upwind-DRP-6 | 1.60 s | 1.6567E+02 |

The combined fQ8/Q8/Q4 and three-family suite passed all six tests in 7.68 s.
These fixtures establish decomposition consistency, not cross-family equality;
the operators are expected to produce slightly different numerical fields.

Punakha NVHPC qualification of the order-6 fixtures passed on 2026-08-06:

| Configuration | traditional-6 | upwind-6 | upwind-DRP-6 | Total |
|---|---:|---:|---:|---:|
| `cpu-release` | pass, 5.59 s | pass, 5.50 s | pass, 6.03 s | 17.12 s |
| `gpu-h100` | pass, 6.44 s | pass, 6.27 s | pass, 6.77 s | 19.48 s |

All six Punakha checks passed. This closes the point-stencil qualification
gate for the three target order-6 finite-difference families under GNU and
NVHPC. The `gpu-h100` timings still represent host numerical execution because
the kernels have not yet been decorated for OpenACC offload.

## Locked two-block interface oracle

`test_elastic_locked_interface_o6.in` provides the decomposition-compatible
interface fixture missing from the historical 21-point tests. It uses two
41-cubed Cartesian blocks, a traditional order-6 operator, a locked interface,
and a moment source in block 1. The source propagates through the interface and
must produce a nonzero field in both blocks.

The regression compares serial shared ownership (`-np 1`) with distributed
block ownership (`-np 2`) and requires identical formatted per-block global
maxima. Local GNU debug qualification passed in 35.43 s:

```text
block 1 max field: 2.0699E+03
block 2 max field: 1.6389E+03
serial face workspace: 0.693 MiB block + 0.539 MiB interface
```

This exercises interface initialization, rotated and hat workspaces, locked
coupling, wave transmission, MPI block ownership, and shutdown cleanup. The
remaining qualification step is to repeat this oracle with NVHPC
`cpu-release` and `gpu-h100` on Punakha.

Punakha qualification completed on 2026-08-06:

| Configuration | Locked-interface oracle |
|---|---:|
| `cpu-release` | pass, 40.40 s |
| `gpu-h100` | pass, 41.32 s |

Both NVHPC builds reproduced the required one-rank/two-rank locked-interface
consistency. All Phase 2 numerical gates now pass with GNU and NVHPC:
scratch-safety, persistent face ownership/accounting, the three order-6 FD
families, and locked-interface decomposition consistency.

Phase 2 is not yet closed. The roadmap still requires a complete persistent
array inventory, total host/predicted-device memory reporting, an explicit
headroom preflight, and steady-state allocation/thread-safety evidence.
Numerical GPU offload remains intentionally outside Phase 2.
