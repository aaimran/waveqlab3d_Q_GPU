# Phase 3 persistent device-data ownership

Date: 2026-08-06  
Status: complete and qualified on NVIDIA H100 with NVHPC 26.5

## Implementation

Phase 3 establishes one persistent OpenACC lifetime after complete domain and
output initialization and GPU capacity approval. It ends before host ownership
is deallocated by `close_domain`. Numerical kernels intentionally remain on the
host.

The implementation never maps `domain_type` or another allocatable ownership
container. `scripts/generate_device_data_openacc.py` consumes the authoritative
persistent-array inventory and generates explicit runtime operations for all
158 declarations classified as `copyin` or `create`. This covers every
allocated instance of:

- grid and metric arrays;
- material and attenuation properties, states, and rates;
- field/rate and plastic state;
- PML state/rate on all faces;
- physical-boundary mirrors and persistent SAT workspaces;
- moment-source metadata/work arrays;
- interface state/rate and persistent coupling workspaces.

The eight host-only output leaves, eight host/update output leaves, and four
ownership containers are not implicitly copied. The CPU backend implements the
same lifecycle API as no-ops, preserving single-source CPU behavior.

Every nonempty allocated leaf is copied in by exact byte range, checked with
`acc_is_present`, retained across the complete timestep loop, and deleted in
reverse ownership order with `acc_delete_finalize`. Presence and the allocated
leaf count/payload are checked again after the final timestep. Cleanup requires
every leaf to be absent from the OpenACC present table.

An explicit `update_domain_host_data` API updates mutable state from device for
future diagnostics/output. It is not called during normal host-oracle runs. The
Phase 3 smoke enables it once before timestepping to qualify every generated
mutable-leaf update path without introducing an RK transfer.

## Reproducible structural gates

```bash
python3 scripts/inventory_persistent_arrays.py --check
python3 scripts/generate_device_data_openacc.py --check
python3 scripts/audit_steady_state_allocations.py
python3 scripts/audit_steady_state_device_transfers.py
```

Expected results are 178 persistent declarations, 158 device-policy
declarations, and 131 RK-reachable procedures containing neither explicit heap
allocation nor explicit device transfers.

## H100 memory reconciliation

The one-block elastic smoke mapped 96 allocated leaves. The independently
computed inventory and explicit traversal both reported 32.334 MiB. NVHPC's
free-memory property measured a 42.000 MiB allocation delta:

```text
inventory payload:              32.334 MiB
explicit traversal payload:     32.334 MiB
measured free-memory delta:      42.000 MiB
runtime/allocator overhead:       9.666 MiB
```

The smoke enforces that measured use is at least the payload and no more than
the payload plus the larger of 64 MiB or 5%. The observed overhead is within
that bound. NVHPC may retain allocator cache after final deletion, so leak
freedom is decided by the stronger per-leaf present-table absence check rather
than requiring the driver's free-memory counter to return byte-for-byte to its
pre-entry value.

## Transfer evidence

`NVCOMPILER_ACC_NOTIFY=3` on the elastic smoke reported 97 initialization
uploads (96 owned leaves plus one compiler module table), all before the first
timestep header. It reported zero CUDA kernel launches and no upload/download
inside or after the RK loop. The transitive source gate independently covers
all 131 procedures reachable from `time_step_RK` and rejects OpenACC data
directives and runtime transfer calls.

## Qualification results

All focused Phase 3 tests passed on Punakha:

| Configuration/gate | Result |
|---|---:|
| NVHPC CPU oracle: fQ8, plane, Q8/Q4, three order-6 families | 7/7, 30.59 s |
| H100 mapping probe and strict Phase 3 smoke | 2/2, 3.57 s |
| H100 plane, Q8/Q4, both PML variants, two fQ8 coarse-grain modes, three order-6 families, locked interface | 11/11, 105.16 s |
| NVHPC allocation tracker: plane and Q8 | 2/2, 69.57 s |
| Final H100 Q8 and elastic post-change check | 2/2, 14.24 s |

The broader 32-test H100 invocation passed every modern numerical, capacity,
PML, coarse-grain, asymmetric, alias, and expected-rejection test once PRRTE
test-only oversubscription was enabled. Six historical fault-file tests remain
outside the qualified set: four request an obsolete four-rank decomposition
that now correctly fails the 20-point safety bound, and their old truth-data
harness also encounters pre-existing permission-denied files. These are legacy
oracle/harness limitations, not Phase 3 device-data failures; the current
41-cubed locked-interface oracle passed in 41.08 s.

## Phase 3 gate decision

- No-kernel enter/presence/update/exit smoke: PASS.
- Runtime bytes agree with inventory within documented overhead: PASS.
- No full-volume transfer inside RK: PASS.
- Reverse cleanup has no present-table leaves: PASS.
- CPU backend and numerical oracle behavior unchanged: PASS.
- CUDA-aware MPI remains disabled: PASS.

Phase 3 is closed. Phase 4 may begin with low-risk RK vector kernels.

Subsequent status: Phase 4 is now complete; see
`PHASE4_RK_VECTOR_KERNELS.md`. The no-kernel/no-RK-transfer statements above
remain the historical Phase 3 baseline.
