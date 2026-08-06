# Phase 2 scratch and allocation audit

Date: 2026-08-06  
Status: point-stencil scratch corrected; face-workspace ownership pending

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

## Remaining face-sized saved workspaces

The active RK path still contains face-sized `allocatable, save` buffers in:

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

That ownership change will be a separate subphase with locked-interface,
boundary, friction, and multi-block regressions.

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
