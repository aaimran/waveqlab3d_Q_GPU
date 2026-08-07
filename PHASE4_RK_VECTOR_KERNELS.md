# Phase 4 RK vector kernels

Date: 2026-08-06  
Status: complete and qualified on NVIDIA H100 with NVHPC 26.5

## Scope and implementation

Phase 4 offloads the two low-risk Runge-Kutta vector operations while retaining
one numerical source and a CPU backend:

- rate scaling: `DF = A*DF`;
- state update: `F = F + dt*DF`.

All 49 rate-scale and 49 state-update expressions in `fields.f90` now call the
backend API. Coverage includes the main field, every attenuation variant, and
all six PML auxiliary state/rate pairs. The OpenACC implementation uses
explicit gang/vector four-dimensional loops with the contiguous x index
innermost and requires the arrays to be present.

Private explicit-shape storage kernels are intentional. NVHPC associated
assumed-shape descriptors with individual procedures: kernels launched, but a
unit test showed unchanged host-visible results. Passing raw explicit shapes
removed that descriptor ambiguity and produces bit-exact expected results.

## Hybrid synchronization boundary

The spatial RHS and MPI paths remain on the host in Phase 4. Consequently the
OpenACC backend has a visible, temporary synchronization bridge:

- rate scaling uploads `DF`, launches the kernel, then downloads `DF`;
- state update uploads `F` and `DF`, launches the kernel, then downloads `F`.

These are five explicit transfer sites, not implicit compiler copies. In the
qualified 30-stage elastic run they produced 150 bridge transfers in addition
to the 97 Phase 3 initialization uploads. Removing this traffic belongs to the
device-side RHS migration; Phase 4 is a correctness and execution gate, not a
claim of useful speedup.

## Reproducible gates

```bash
python3 scripts/normalize_rk_vector_updates.py
python3 scripts/audit_steady_state_allocations.py
python3 scripts/audit_steady_state_device_transfers.py
```

Expected results are 49/49 backend calls, 137 RK-reachable procedures without
explicit allocation, and exactly five explicit transfer sites confined to the
Phase 4 bridge. OpenACC CTest also provides `rk_vector_kernel_launch`, which
requires exactly one launch of each named CUDA kernel, zero numerical error,
and no implicit device allocation in NVHPC notifications.

## Qualification results

The asymmetric unit fixture uses non-unit-bound 7x5x3x4 arrays, a rate factor
of -0.375, and an update increment of 0.125. Both reported maximum errors were
exactly zero.

| Configuration/gate | Result |
|---|---:|
| GNU CPU release focused suite | 8/8, 29.60 s |
| NVHPC CPU allocation-audit suite | 3/3, 69.16 s |
| H100 integrated focused suite | 12/12, 116.36 s |
| Final H100 unit and launch regression gates | 2/2, 1.64 s |

The H100 launch notification reported one `scale_rate_kernel` and one
`update_state_kernel`, each with four gangs and vector length 128. The
integrated elastic run launched 30 of each kernel with no implicit allocation;
its first RK launch used 7,301 gangs and vector length 128. The final elastic
diagnostic remained `max|field|=1.6623E+02`.

The integrated suite covered elastic plane output, Q8/Q4 decomposition, all
three order-6 operator families, the locked interface, Q4/Q8 PML, and fQ8
coarse-grain modes 2 and 0. CUDA-aware MPI remains disabled.

## Gate decision

- CPU and OpenACC backends preserve the numerical oracle: PASS.
- All field, attenuation, and PML RK vector updates use the backend: PASS.
- Named kernels execute on H100 with explicit launch geometry: PASS.
- No implicit allocation or transfer is introduced: PASS.
- Explicit hybrid synchronization is measured and documented: PASS.

Phase 4 is closed. Phase 5 can begin with the narrow traditional Cartesian
elastic RHS path before expanding to other operators and physics.
